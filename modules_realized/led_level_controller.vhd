library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity led_level_controller is
    Generic (
        NUM_LEDS : positive := 16;
        CHANNEL_LENGTH : positive := 24; -- 3 Byte for AXIS audio I2S
        REFRESH_TIME_MS: positive := 1; -- refresh the LEDS every REFRESH_TIME_MS
        CLOCK_PERIOD_NS: positive := 10 -- base time
    );
    Port (
        aclk : in std_logic;
        aresetn : in std_logic;

        s_axis_tvalid : in std_logic;
        s_axis_tdata : in std_logic_vector(CHANNEL_LENGTH-1 downto 0);
        s_axis_tlast : in std_logic;
        s_axis_tready : out std_logic;

        led : out std_logic_vector(NUM_LEDS-1 downto 0)
    );
end led_level_controller;

architecture Behavioral of led_level_controller is

    ---------- CONSTANTS ----------
    constant REFRESH_CYCLES : integer := REFRESH_TIME_MS * (1_000_000 / CLOCK_PERIOD_NS);
    constant LOG_OFFSET : integer := CHANNEL_LENGTH - NUM_LEDS; -- Bit offset for logarithmic scale mapping from last audio L/R average level to led pattern
    -------------------------------

    ---------- SIGNALS ----------
    signal timer_cnt : integer range 0 to REFRESH_CYCLES-1 := 0; -- Timer to achieve the desired refresh rate
    signal abs_l : unsigned(CHANNEL_LENGTH-1 downto 0) := (others => '0');
    signal avg_level : unsigned(CHANNEL_LENGTH-1 downto 0) := (others => '0');
    signal reg_led : std_logic_vector(NUM_LEDS-1 downto 0) := (others => '0');
    -----------------------------

    ---------- FUNCTIONS ----------
    -- Function to calculate the absolute value of a signed std_logic_vector and return it as unsigned
    function get_absolute_value(data_in : std_logic_vector) return unsigned is
        variable result : unsigned(data_in'length-1 downto 0);
    begin
        if data_in(data_in'high) = '1' then -- If MSB is '1' the number is negative
            result := unsigned(not data_in) + 1; -- Two's complement inversion
        else
            result := unsigned(data_in);
        end if;
        return result;
    end function;

    -- Function to map the last audio L/R average level to the corresponding led pattern on a logarithmic scale
    function level_to_leds(level : unsigned) return std_logic_vector is
        variable next_led : std_logic_vector(NUM_LEDS-1 downto 0) := (others => '0');
    begin
        -- Scan from highest bit down to locate the level magnitude
        for i in NUM_LEDS-1 downto 0 loop
            if level(i + LOG_OFFSET) = '1' then
                -- Fill the leds up to the level magnitude + offset (i + LOG_OFFSET) position
                for j in 0 to i loop
                    next_led(j) := '1';
                end loop;
                exit; -- Exit the loop early once the highest bit is found
            end if;
        end loop;
    
        return next_led;
    end function;
    -------------------------------

begin
    
    ---------- DATA FLOW ----------
    led <= reg_led;
    -------------------------------

    ---------- PROCESSES ----------
    process (aclk)
        variable current_abs : unsigned(CHANNEL_LENGTH-1 downto 0);
        variable sum_level : unsigned(CHANNEL_LENGTH downto 0); -- CHANNEL_LENGTH instead of CHANNEL_LENGTH-1 to safely perform addition without overflow risk
    begin
        if rising_edge(aclk) then
            if aresetn = '0' then
                s_axis_tready <= '0';
                timer_cnt <= 0;
                abs_l <= (others => '0');
                avg_level <= (others => '0');
                reg_led <= (others => '0');
            else
                -- Always ready to accept data from the bus (audio monitor is non-blocking), except when reset is active
                s_axis_tready <= '1';
                
                -- Refresh timer and led update logic (runs every REFRESH_CYCLES)
                if timer_cnt = REFRESH_CYCLES-1 then
                    -- Update led register and reset the refreshing counter for the next refreshing window
                    timer_cnt <= 0;
                    reg_led <= level_to_leds(avg_level);
                else
                    timer_cnt <= timer_cnt + 1;
                end if;

                -- Audio data (L/R channels) capture and average logic
                if s_axis_tvalid = '1' then
                    
                    -- Get absolute value of the signed audio sample
                    current_abs := get_absolute_value(s_axis_tdata);

                    -- Process L/R channels' samples
                    if s_axis_tlast = '0' then
                        -- Left channel: store for later
                        abs_l <= current_abs;
                    else
                        -- Right channel: average with left channel
                        sum_level := resize(abs_l, CHANNEL_LENGTH+1) + resize(current_abs, CHANNEL_LENGTH+1);
                        avg_level <= sum_level(CHANNEL_LENGTH downto 1);
                    end if;
                    
                end if;

            end if;
        end if;
    end process;
    -------------------------------

end Behavioral;
