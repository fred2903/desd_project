library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity reverb is
    Generic (
        LOG2_DELAY_INCR : integer := 1; -- CONSTANT DO NOT TOUCH
        CHANNEL_LENGTH : integer := 24; -- 3 byte for audio
        DELAY_LENGTH : integer := 10; -- JSTK axis dimension
        DELAY_INIT : integer := 882; -- 20 ms INIT VALUE DO NOT TOUCH
        GAIN_LENGTH : integer := 10; -- JSTK axis dimension
        GAIN_INIT_FRAC : integer := 614; -- 614/(2^10) ~= 0.6 INIT VALUE DO NOT TOUCH
        HIGHER_BOUND : integer := 2**23-1; -- Inclusive (max value of TDATA at 24 bit signed)
		LOWER_BOUND : integer := -2**23 -- Inclusive (min value of TDATA at 24 bit signed)
    );
    Port (
        aclk : in std_logic;
        aresetn : in std_logic;
    
        s_axis_tvalid : in std_logic;
        s_axis_tdata : in std_logic_vector(CHANNEL_LENGTH-1 downto 0);
        s_axis_tlast : in std_logic;
        s_axis_tready : out std_logic;
    
        m_axis_tvalid : out std_logic;
        m_axis_tdata : out std_logic_vector(CHANNEL_LENGTH-1 downto 0);
        m_axis_tlast : out std_logic;
        m_axis_tready : in std_logic;

        enable_reverb : in std_logic;
        delay_in : in std_logic_vector(DELAY_LENGTH-1 downto 0);
        gain_in : in std_logic_vector(GAIN_LENGTH-1 downto 0)
    );
end reverb;

architecture Behavioral of reverb is

    ---------- INTERNAL COMPONENTS ----------
    component delay is
        Generic (
            CHANNEL_LENGTH : integer;
            DELAY_LENGTH : integer;
            DELAY_INIT : integer;
            LOG2_DELAY_INCR : integer
        );
        Port (
            aclk : in std_logic;
            aresetn : in std_logic;
            
            delay_in : in std_logic_vector(DELAY_LENGTH-1 downto 0);
            data_in : in std_logic_vector(CHANNEL_LENGTH-1 downto 0);
            data_in_valid : in std_logic;
        
            data_out : out std_logic_vector(CHANNEL_LENGTH-1 downto 0)
        );
    end component;
    -----------------------------------------

    ---------- TYPES ----------
    type state_type is (WAIT_DATA, COMPUTE_1, COMPUTE_2, SEND_DATA);
    ---------------------------

    ---------- SIGNALS ----------
    signal x_n : std_logic_vector(CHANNEL_LENGTH-1 downto 0);
    signal reg_last : std_logic;
    signal reg_enable_reverb : std_logic;
    signal reg_delay : std_logic_vector(DELAY_LENGTH-1 downto 0);
    signal reg_gain : std_logic_vector(GAIN_LENGTH-1 downto 0);
    signal state : state_type := WAIT_DATA;
    signal mul_res : signed(CHANNEL_LENGTH+GAIN_LENGTH downto 0); -- CHANNEL_LENGTH+GAIN_LENGTH to safely perform multiplication without overflow risk
    signal y_n : std_logic_vector(CHANNEL_LENGTH-1 downto 0);
    signal delay_data_in_valid_l : std_logic;
    signal delay_data_in_valid_r : std_logic;
    signal delay_data_out_l : std_logic_vector(CHANNEL_LENGTH-1 downto 0);
    signal delay_data_out_r : std_logic_vector(CHANNEL_LENGTH-1 downto 0);
    -----------------------------

    ---------- FUNCTIONS ----------
    -- Function to clip the output data to the valid range [LOWER_BOUND, HIGHER_BOUND] of signed 24-bit audio
    function clip_data(input_val : signed) return std_logic_vector is
    begin
        if input_val > to_signed(HIGHER_BOUND, input_val'length) then
            return std_logic_vector(to_signed(HIGHER_BOUND, CHANNEL_LENGTH));
        elsif input_val < to_signed(LOWER_BOUND, input_val'length) then
            return std_logic_vector(to_signed(LOWER_BOUND, CHANNEL_LENGTH));
        else
            return std_logic_vector(resize(input_val, CHANNEL_LENGTH));
        end if;
    end function;
    -------------------------------

begin
    
    ---------- INTERNAL COMPONENTS INSTANTIATIONS ----------
    -- Left channel delay line
    delay_inst_l : delay
        Generic map (
            CHANNEL_LENGTH => CHANNEL_LENGTH,
            DELAY_LENGTH => DELAY_LENGTH,
            DELAY_INIT => DELAY_INIT,
            LOG2_DELAY_INCR => LOG2_DELAY_INCR
        )
        Port map (
            aclk => aclk,
            aresetn => aresetn,
            delay_in => reg_delay,
            data_in => y_n,
            data_in_valid => delay_data_in_valid_l,
            data_out => delay_data_out_l
        );
    
    -- Right channel delay line
    delay_inst_r : delay
        Generic map (
            CHANNEL_LENGTH => CHANNEL_LENGTH,
            DELAY_LENGTH => DELAY_LENGTH,
            DELAY_INIT => DELAY_INIT,
            LOG2_DELAY_INCR => LOG2_DELAY_INCR
        )
        Port map (
            aclk => aclk,
            aresetn => aresetn,
            delay_in => reg_delay,
            data_in => y_n,
            data_in_valid => delay_data_in_valid_r,
            data_out => delay_data_out_r
        );
    --------------------------------------------------------

    ---------- AXI4-STREAM OUTPUT FSM ----------
	with state select s_axis_tready <=
        '1' when WAIT_DATA,
        '0' when others;

    with state select m_axis_tvalid <=
        '1' when SEND_DATA,
        '0' when others;

    with state select m_axis_tdata <=
        y_n when SEND_DATA,
        (others => '-') when others;
        
    with state select m_axis_tlast <=
        reg_last when SEND_DATA,
        '0' when others;
	--------------------------------------------

    ---------- DELAY COMPONENT INPUT FSM ----------
    delay_data_in_valid_l <= '1' when (state = SEND_DATA and m_axis_tready = '1' and reg_last = '0') else '0';
    
    delay_data_in_valid_r <= '1' when (state = SEND_DATA and m_axis_tready = '1' and reg_last = '1') else '0';
    -----------------------------------------------

    ---------- PROCESSES ----------
    process (aclk)
        variable data_gain : signed(CHANNEL_LENGTH-1 downto 0);
        variable sum_res : signed(CHANNEL_LENGTH downto 0); -- CHANNEL_LENGTH instead of CHANNEL_LENGTH-1 to safely perform addition without overflow risk
        variable active_delay_out : std_logic_vector(CHANNEL_LENGTH-1 downto 0); -- Holds selected channel y[n - delay_in]
    begin
        if rising_edge(aclk) then
            if aresetn = '0' then
                state <= WAIT_DATA;
            else
                case state is
                
                    -- Wait for upstream tvalid high, then capture input data and move to COMPUTE state
                    when WAIT_DATA =>

                        if s_axis_tvalid = '1' then
                            x_n <= s_axis_tdata;
                            reg_last <= s_axis_tlast;
                            reg_enable_reverb <= enable_reverb;
                            reg_delay <= delay_in;
                            reg_gain <= gain_in;
                            state <= COMPUTE_1;
                        end if;

                    -- Apply reverb effect if enabled, then move to SEND_DATA state
                    when COMPUTE_1 =>
                        -- Multiplex y[n - delay_in] based on which channel is being processed
                        if reg_last = '0' then
                            active_delay_out := delay_data_out_l;
                        else -- reg_last = '1'
                            active_delay_out := delay_data_out_r;
                        end if;
                        
                        -- mul_res = gain_in * y[n - delay_in]
                        mul_res <= signed('0' & reg_gain) * signed(active_delay_out); -- Append '0' to gain_in to safely convert it to signed while maintaining it positive
                        
                        state <= COMPUTE_2;

                    -- Apply reverb effect if enabled, then move to SEND_DATA state
                    when COMPUTE_2 =>
                        if reg_enable_reverb = '1' then -- Reverb is enabled: apply the effect
                            
                            -- data_gain = mul_res / 2^gain_length
                            data_gain := resize(mul_res(mul_res'high downto GAIN_LENGTH), CHANNEL_LENGTH);
                            
                            -- sum_res = x[n] + data_gain
                            sum_res := resize(signed(x_n), CHANNEL_LENGTH+1) + resize(data_gain, CHANNEL_LENGTH+1);
                            
                            -- y[n] = sat(sum_res)
                            y_n <= clip_data(sum_res);

                        else -- Reverb is bypassed: pass the raw audio straight through
                            y_n <= x_n;
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
