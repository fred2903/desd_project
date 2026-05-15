library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity moving_average is
    Generic (
        LOG2_LEN: positive := 5; -- Perform the average over 2^LOG2_LEN samples
        CHANNEL_LENGTH : integer := 24 -- 3 Byte for AXIS audio I2S
    );
    Port ( 
        s_axis_tready : out std_logic;
        s_axis_tdata : in std_logic_vector(CHANNEL_LENGTH-1 downto 0);
        s_axis_tlast : in std_logic;
        s_axis_tvalid : in std_logic;

        m_axis_tvalid : out std_logic;
        m_axis_tdata : out std_logic_vector(CHANNEL_LENGTH-1 downto 0);
        m_axis_tready : in std_logic;
        m_axis_tlast : out std_logic;

        enable_filter: in std_logic;

        aclk : in std_logic;
        aresetn : in std_logic
    );
end moving_average;

architecture Behavioral of moving_average is

    ---------- CONSTANTS ----------
    constant FIFO_DEPTH : positive := 2**LOG2_LEN;
    -------------------------------
    
    ---------- TYPES ----------
    type state_type is (WAIT_DATA, COMPUTE, SEND_DATA);
    type fifo_type is array (0 to FIFO_DEPTH-1) of signed(CHANNEL_LENGTH-1 downto 0);
    ---------------------------

    ---------- SIGNALS ----------
    signal reg_data : signed(CHANNEL_LENGTH-1 downto 0);
    signal reg_last : std_logic;
    signal reg_enable_filter : std_logic;
    signal state : state_type := WAIT_DATA;
    signal reg_sum_l : signed(CHANNEL_LENGTH+LOG2_LEN-1 downto 0) := (others => '0');
    signal fifo_l : fifo_type := (others => (others => '0'));
    signal ptr_l : unsigned(LOG2_LEN-1 downto 0) := (others => '0');
    signal reg_sum_r : signed(CHANNEL_LENGTH+LOG2_LEN-1 downto 0) := (others => '0');
    signal fifo_r : fifo_type := (others => (others => '0'));
    signal ptr_r : unsigned(LOG2_LEN-1 downto 0) := (others => '0');
    signal processed_data : std_logic_vector(CHANNEL_LENGTH-1 downto 0);
    -----------------------------
    
begin

    ---------- AXI4-STREAM OUTPUT FSM ----------
    with state select s_axis_tready <=
        '1' when WAIT_DATA, 
        '0' when others;

    with state select m_axis_tvalid <=
        '1' when SEND_DATA, 
        '0' when others;

    with state select m_axis_tdata <=
        processed_data when SEND_DATA,
        (others => '-') when others;

    with state select m_axis_tlast <=
        reg_last when SEND_DATA,
        '0' when others;
    --------------------------------------------

    ---------- PROCESSES ----------
    process (aclk)
        variable oldest_sample : signed(CHANNEL_LENGTH-1 downto 0);
        variable next_sum : signed(reg_sum_l'range);
    begin
        if rising_edge(aclk) then
            if aresetn = '0' then
                state <= WAIT_DATA;
                reg_sum_l <= (others => '0');
                fifo_l <= (others => (others => '0'));
                ptr_l <= (others => '0');
                reg_sum_r <= (others => '0');
                fifo_r <= (others => (others => '0'));
                ptr_r <= (others => '0');
            else
                case state is

                    -- Wait for upstream tvalid high, then capture input data and move to COMPUTE state
                    when WAIT_DATA =>
                        if s_axis_tvalid = '1' then
                            reg_data <= signed(s_axis_tdata);
                            reg_last <= s_axis_tlast;
                            reg_enable_filter <= enable_filter;
                            state <= COMPUTE;
                        end if;

                    -- Compute the moving average with the new sample, then move to SEND_DATA state
                    when COMPUTE =>

                        -- Process the sample based on which channel it belongs to and update the corresponding FIFO and running sum
                        if reg_last = '0' then -- Left channel sample

                            -- Update running sum (new_sum = old_sum + new_sample - old_sample)
                            oldest_sample := fifo_l(to_integer(ptr_l));
                            next_sum := reg_sum_l + reg_data - oldest_sample;
                            reg_sum_l <= next_sum;

                            -- Store new sample in FIFO and increment pointer
                            fifo_l(to_integer(ptr_l)) <= reg_data;
                            ptr_l <= ptr_l + 1; -- Pointer will wrap around due to unsigned overflow, creating a circular buffer

                        else -- Right channel sample

                            -- Update running sum (new_sum = old_sum + new_sample - old_sample)
                            oldest_sample := fifo_r(to_integer(ptr_r));
                            next_sum := reg_sum_r + reg_data - oldest_sample;
                            reg_sum_r <= next_sum;

                            -- Store new sample in FIFO and increment pointer
                            fifo_r(to_integer(ptr_r)) <= reg_data;
                            ptr_r <= ptr_r + 1; -- Pointer will wrap around due to unsigned overflow, creating a circular buffer

                        end if;

                        -- Assign output based on filter enable
                        if reg_enable_filter = '1' then
                            -- Division by the number of samples in the FIFO 2^LOG2_LEN using left shift
                            processed_data <= std_logic_vector(next_sum(CHANNEL_LENGTH+LOG2_LEN-1 downto LOG2_LEN));
                        else
                            processed_data <= std_logic_vector(reg_data);
                        end if;

                        state <= SEND_DATA;

                    -- Wait for downstream tready high, then move back to WAIT_DATA state to process the next sample
                    when SEND_DATA =>
                        if m_axis_tready = '1' then
                            state <= WAIT_DATA;
                        end if;

                end case;
            end if;
        end if;
    end process;
    -------------------------------

end Behavioral;
