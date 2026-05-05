library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity reverb is
    generic(
        LOG2_DELAY_INCR : integer :=1;              -- CONSTANT DO NOT TOUCH
        CHANNEL_LENGHT  : integer := 24;            -- 3 byte for audio
        DELAY_LENGHT    : integer := 10;            -- JSTK axis dimension
        DELAY_INIT      : integer := 882;           -- 20 ms INIT VALUE DO NOT TOUCH
        GAIN_LENGHT     : integer := 10;            -- JSTK axis dimension
        GAIN_INIT_FRAC  : integer := 614;           -- 614/(2^10) ~= 0.6 INIT VALUE DO NOT TOUCH
        HIGHER_BOUND    : integer := 2**23-1;       -- Inclusive (max value of TDATA at 24 bit signed)
        LOWER_BOUND     : integer := -2**23         -- Inclusive (min value of TDATA at 24 bit signed)
    );
    Port (
        aclk            : in std_logic;
        aresetn         : in std_logic;
        
        enable_reverb   : in std_logic;
        delay_in        : in std_logic_vector(DELAY_LENGHT-1 downto 0);
        gain_in         : in std_logic_vector(GAIN_LENGHT-1 downto 0);
    
        s_axis_tvalid   : in std_logic;
        s_axis_tdata    : in std_logic_vector(CHANNEL_LENGHT-1 downto 0);
        s_axis_tlast    : in std_logic;
        s_axis_tready   : out std_logic;
    
        m_axis_tvalid   : out std_logic;
        m_axis_tdata    : out std_logic_vector(CHANNEL_LENGHT-1 downto 0);
        m_axis_tlast    : out std_logic;
        m_axis_tready   : in std_logic
    );
end reverb;

architecture Behavioral of reverb is

    component delay is
        generic(
            CHANNEL_LENGHT  : integer;
            DELAY_LENGHT    : integer;
            DELAY_INIT      : integer;
            LOG2_DELAY_INCR : integer
        );
        Port (
            aclk            : in std_logic;
            aresetn         : in std_logic;
            delay_in        : in std_logic_vector(DELAY_LENGHT-1 downto 0);
            data_in         : in std_logic_vector(CHANNEL_LENGHT-1 downto 0);
            data_in_valid   : in std_logic;
            data_out        : out std_logic_vector(CHANNEL_LENGHT-1 downto 0)
        );
    end component;

    --FSM
    type CURRENT_STATE_TYPE is (WAIT_LEFT, WAIT_RIGHT, MULTIPLICATION, ADD_DIVISION, SATURATION, SEND_LEFT, SEND_RIGHT);
    signal CURRENT_STATE    : CURRENT_STATE_TYPE;
    
    --
    signal enable_reverb_left, write_delay_valid : std_logic;
    
    --reg
    signal left_channel, right_channel : std_logic_vector(CHANNEL_LENGHT-1 downto 0);
    
    --operation reg
    signal yn, delayed_yn : std_logic_vector(CHANNEL_LENGHT-1 downto 0);
    signal mul_res : signed(CHANNEL_LENGHT + GAIN_LENGHT downto 0);
    signal sum_res : signed(CHANNEL_LENGHT downto 0);

    signal yn_right, delayed_yn_right : std_logic_vector(CHANNEL_LENGHT-1 downto 0);
    signal mul_res_right : signed(CHANNEL_LENGHT + GAIN_LENGHT downto 0);
    signal sum_res_right : signed(CHANNEL_LENGHT downto 0);

begin

    with CURRENT_STATE select m_axis_tvalid <=
        '1' when SEND_LEFT,
        '1' when SEND_RIGHT,
        '0' when others;

    with CURRENT_STATE select s_axis_tready <=
        '1' when WAIT_LEFT,
        '1' when WAIT_RIGHT,
        '0' when others;

    with CURRENT_STATE select m_axis_tdata <=
        yn               when SEND_LEFT,
        yn_right         when SEND_RIGHT,
        (others => '-')  when others;

    with CURRENT_STATE select m_axis_tlast <=
        '0' when SEND_LEFT,
        '1' when SEND_RIGHT,
        '0' when others;

    --------------------------------------
    delay_inst : delay
    generic map (
        CHANNEL_LENGHT  => CHANNEL_LENGHT,
        DELAY_LENGHT    => DELAY_LENGHT,
        DELAY_INIT      => DELAY_INIT,
        LOG2_DELAY_INCR => LOG2_DELAY_INCR
    )
    port map (
        aclk            => aclk,
        aresetn         => aresetn,
        delay_in        => delay_in,
        data_in         => yn,
        data_in_valid   => write_delay_valid,
        data_out        => delayed_yn
    );

    delay_inst_right : delay
    generic map (
        CHANNEL_LENGHT  => CHANNEL_LENGHT,
        DELAY_LENGHT    => DELAY_LENGHT,
        DELAY_INIT      => DELAY_INIT,
        LOG2_DELAY_INCR => LOG2_DELAY_INCR
    )
    port map (
        aclk            => aclk,
        aresetn         => aresetn,
        delay_in        => delay_in,
        data_in         => yn_right,
        data_in_valid   => write_delay_valid,
        data_out        => delayed_yn_right
    );
    -----------------------------------------

    process (aclk)
        variable data_gain_var : signed(CHANNEL_LENGHT - 1 downto 0);
        variable data_gain_var_right : signed(CHANNEL_LENGHT - 1 downto 0);
    begin
        if rising_edge(aclk) then
            if aresetn = '0' then
                CURRENT_STATE     <= WAIT_LEFT;
                write_delay_valid <= '0';
                yn                <= (others => '0');
                yn_right          <= (others => '0');
            else

                case CURRENT_STATE is
                    when WAIT_LEFT =>
                        if s_axis_tvalid = '1' then
                            if  s_axis_tlast = '0' then
                                left_channel  <= s_axis_tdata;
                                CURRENT_STATE <= WAIT_RIGHT;
                            else
                                CURRENT_STATE <= WAIT_LEFT;
                            end if;
                        end if;
                        --check that in left and right channel enable_reverb is on
                        enable_reverb_left <= enable_reverb;
                        --use the component delay to compute y(n-delay_in only at the end)
                        write_delay_valid <= '0';

                    when WAIT_RIGHT =>
                        if s_axis_tvalid = '1' then
                            if  s_axis_tlast = '1' then
                                right_channel  <= s_axis_tdata;

                                if enable_reverb = '1' and enable_reverb_left = '1' then
                                    --perform reverb
                                    CURRENT_STATE <= MULTIPLICATION;
                                else
                                    --skip the reverb, and act like as a wire
                                    CURRENT_STATE <= SEND_LEFT;
                                    yn            <= left_channel;
                                    yn_right      <= s_axis_tdata;     
                                end if;
                            else
                                CURRENT_STATE <= WAIT_LEFT;
                            end if;
                        end if;

                    when MULTIPLICATION =>
                        mul_res       <= signed(delayed_yn) * signed("0" & gain_in);
                        mul_res_right <= signed(delayed_yn_right) * signed("0" & gain_in);
                        CURRENT_STATE <= ADD_DIVISION;

                    when ADD_DIVISION =>
                        data_gain_var := mul_res(CHANNEL_LENGHT + GAIN_LENGHT - 1 downto GAIN_LENGHT);
                        sum_res <= resize(signed(left_channel), CHANNEL_LENGHT + 1) + resize(data_gain_var, CHANNEL_LENGHT + 1);

                        data_gain_var_right := mul_res_right(CHANNEL_LENGHT + GAIN_LENGHT - 1 downto GAIN_LENGHT);
                        sum_res_right <= resize(signed(right_channel), CHANNEL_LENGHT + 1) + resize(data_gain_var_right, CHANNEL_LENGHT + 1);
                        
                        CURRENT_STATE <= SATURATION;

                    when SATURATION =>

                        if sum_res > to_signed(HIGHER_BOUND, CHANNEL_LENGHT + 1) then
                            yn <= std_logic_vector(to_signed(HIGHER_BOUND, CHANNEL_LENGHT));
                        elsif sum_res < to_signed(LOWER_BOUND, CHANNEL_LENGHT + 1) then
                            yn <= std_logic_vector(to_signed(LOWER_BOUND, CHANNEL_LENGHT));
                        else
                            yn <= std_logic_vector(sum_res(CHANNEL_LENGHT-1 downto 0));
                        end if;
                        

                        if sum_res_right > to_signed(HIGHER_BOUND, CHANNEL_LENGHT + 1) then
                            yn_right <= std_logic_vector(to_signed(HIGHER_BOUND, CHANNEL_LENGHT));
                        elsif sum_res_right < to_signed(LOWER_BOUND, CHANNEL_LENGHT + 1) then
                            yn_right <= std_logic_vector(to_signed(LOWER_BOUND, CHANNEL_LENGHT));
                        else
                            yn_right <= std_logic_vector(sum_res_right(CHANNEL_LENGHT-1 downto 0));
                        end if;

                        CURRENT_STATE <= SEND_LEFT;

                    when SEND_LEFT =>
                        if m_axis_tready = '1' then
                            CURRENT_STATE <= SEND_RIGHT;
                        end if;

                    when SEND_RIGHT =>
                        if m_axis_tready = '1' then
                            CURRENT_STATE     <= WAIT_LEFT;
                            write_delay_valid <= '1';
                        end if;

                end case;
            end if;
        end if;
    end process;
end Behavioral;