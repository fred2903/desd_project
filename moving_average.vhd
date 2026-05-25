library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity moving_average is
    Generic (
        LOG2_LEN: positive := 5; -- Perform the average over 2^LOG2_LEN samples
        CHANNEL_LENGTH : integer := 24 -- 3 Byte for AXIS audio I2S
    );
    Port (
        aclk : in std_logic;
        aresetn : in std_logic;

        s_axis_tready : out std_logic;
        s_axis_tdata : in std_logic_vector(CHANNEL_LENGTH-1 downto 0);
        s_axis_tlast : in std_logic;
        s_axis_tvalid : in std_logic;

        m_axis_tvalid : out std_logic;
        m_axis_tdata : out std_logic_vector(CHANNEL_LENGTH-1 downto 0);
        m_axis_tready : in std_logic;
        m_axis_tlast : out std_logic;

        enable_filter: in std_logic
    );
end moving_average;

architecture Behavioral of moving_average is

    ---------- CONSTANTS ----------
    constant FIFO_DEPTH : integer := 2**LOG2_LEN;
    -------------------------------
    
    ---------- TYPES ----------
    type state_type is (WAIT_DATA, COMPUTE_1, COMPUTE_2, SEND_DATA);
    type fifo_type is array (0 to FIFO_DEPTH-1) of signed(CHANNEL_LENGTH-1 downto 0);
    ---------------------------

    ---------- SIGNALS ----------
    signal reg_data : signed(CHANNEL_LENGTH-1 downto 0);
    signal reg_last : std_logic;
    signal reg_enable_filter : std_logic;
    signal state : state_type := WAIT_DATA;
    signal reg_sum_l : signed(CHANNEL_LENGTH+LOG2_LEN-1 downto 0) := (others => '0');
    signal fifo_l : fifo_type;
    signal ptr_l : unsigned(LOG2_LEN-1 downto 0) := (others => '0');
    signal wrapped_l : std_logic := '0';
    signal reg_sum_r : signed(CHANNEL_LENGTH+LOG2_LEN-1 downto 0) := (others => '0');
    signal fifo_r : fifo_type;
    signal ptr_r : unsigned(LOG2_LEN-1 downto 0) := (others => '0');
    signal wrapped_r : std_logic := '0';
    signal reg_oldest : signed(CHANNEL_LENGTH-1 downto 0);
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
        variable next_sum : signed(reg_sum_l'range);
    begin
        if rising_edge(aclk) then
            if aresetn = '0' then
                -- Instead of resetting the FIFO arrays, which would require iterating over all their entries, it is possible to simply reset the pointers and wrapped flags to create the effect of empty FIFOs until they get filled up with new incoming samples. This approach is more efficient in terms of resources usage (BRAM-allocation friendly) and avoids unnecessary writes to the FIFO arrays, which can be large depending on the value of LOG2_LEN
                state <= WAIT_DATA;
                reg_sum_l <= (others => '0');
                ptr_l <= (others => '0');
                wrapped_l <= '0';
                reg_sum_r <= (others => '0');
                ptr_r <= (others => '0');
                wrapped_r <= '0';
            else
                case state is

                    -- Wait for upstream tvalid high, then capture input data and move to COMPUTE_1 state
                    when WAIT_DATA =>
                        if s_axis_tvalid = '1' then
                            reg_data <= signed(s_axis_tdata);
                            reg_last <= s_axis_tlast;
                            reg_enable_filter <= enable_filter;
                            state <= COMPUTE_1;
                        end if;

                    -- Compute the moving average with the new sample in the next two states (COMPUTE_1 and COMPUTE_2), considering if the filter is enabled
                    when COMPUTE_1 =>

                        -- Retrieve the oldest sample based on which channel is active
                        if reg_last = '0' then -- Left channel sample

                            if wrapped_l = '1' then -- fifo_l has been filled at least once, so the value at ptr_l is valid
                                reg_oldest <= fifo_l(to_integer(ptr_l));
                            else -- Safely ignore fifo_l junk values
                                reg_oldest <= (others => '0');
                            end if;

                        else -- Right channel sample

                            if wrapped_r = '1' then -- fifo_r has been filled at least once, so the value at ptr_r is valid
                                reg_oldest <= fifo_r(to_integer(ptr_r));
                            else -- Safely ignore fifo_r junk values
                                reg_oldest <= (others => '0');
                            end if;

                        end if;

                        state <= COMPUTE_2;
                    
                    when COMPUTE_2 =>

                        -- Process the new sample based on which channel it belongs to and update the corresponding FIFO and running sum
                        if reg_last = '0' then -- Left channel sample

                            -- Update running sum (new_sum = old_sum + new_sample - old_sample)
                            next_sum := reg_sum_l + reg_data - reg_oldest;
                            reg_sum_l <= next_sum;

                            -- Store new sample in fifo_l, check if ptr_l is about to roll over in order to set wrapped_l flag and increment ptr_l
                            fifo_l(to_integer(ptr_l)) <= reg_data;
                            if ptr_l = FIFO_DEPTH-1 then
                                wrapped_l <= '1';
                            end if;
                            ptr_l <= ptr_l + 1; -- Pointer will wrap around due to unsigned overflow, creating a circular buffer

                        else -- Right channel sample

                            -- Update running sum (new_sum = old_sum + new_sample - old_sample)
                            next_sum := reg_sum_r + reg_data - reg_oldest;
                            reg_sum_r <= next_sum;

                            -- Store new sample in fifo_r, check if ptr_r is about to roll over in order to set wrapped_r flag and increment ptr_r
                            fifo_r(to_integer(ptr_r)) <= reg_data;
                            if ptr_r = FIFO_DEPTH-1 then
                                wrapped_r <= '1';
                            end if;
                            ptr_r <= ptr_r + 1; -- Pointer will wrap around due to unsigned overflow, creating a circular buffer

                        end if;

                        -- Assign output based on filter enable
                        if reg_enable_filter = '1' then
                            -- Division by the number of samples in the FIFO 2^LOG2_LEN using shift left
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
