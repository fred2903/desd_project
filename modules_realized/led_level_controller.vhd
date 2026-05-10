----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 22.05.2021 15:42:35
-- Design Name: 
-- Module Name: led_level_controller - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity led_level_controller is

    generic(

        NUM_LEDS : positive := 16;
        CHANNEL_LENGHT  : positive := 24;   -- 3 Byte for AXIS audio I2S
        refresh_time_ms: positive :=1;      -- refresh the LEDS every refresh_time_ms
        clock_period_ns: positive :=10      -- base time

    );
    Port (
        aclk			: in std_logic;
        aresetn			: in std_logic;
        
        led    : out std_logic_vector(NUM_LEDS-1 downto 0);

        s_axis_tvalid	: in std_logic;
        s_axis_tdata	: in std_logic_vector(CHANNEL_LENGHT-1 downto 0);
        s_axis_tlast    : in std_logic;
        s_axis_tready	: out std_logic

    );
end led_level_controller;



architecture Behavioral of led_level_controller is

    constant REFRESH_CYCLES : positive :=
        (refresh_time_ms * 1000000) / clock_period_ns;

    signal refresh_counter : natural range 0 to REFRESH_CYCLES := 0;

    signal left_abs        : unsigned(CHANNEL_LENGHT-1 downto 0) := (others => '0');
    signal avg_level       : unsigned(CHANNEL_LENGHT-1 downto 0) := (others => '0');

    signal led_reg         : std_logic_vector(NUM_LEDS-1 downto 0) := (others => '0');

    ----------------FUNCTIONS----------------

    --Funtion1:Absolute value of a signed sample

    function abs_sample(
        sample : std_logic_vector(CHANNEL_LENGHT-1 downto 0)
    ) return unsigned is
        variable mag : unsigned(CHANNEL_LENGHT-1 downto 0);

    begin
        if sample(CHANNEL_LENGHT-1) = '1' then
            mag := unsigned(not sample) + 1;
        else
            mag := unsigned(sample);
        end if;

        return mag;
    end function;


    -- Function2: Exponential mapping of level to LED count
   
     function level_to_leds(
        level : unsigned(CHANNEL_LENGHT-1 downto 0)
    ) return std_logic_vector is

        variable result    : std_logic_vector(NUM_LEDS-1 downto 0);
        variable msb_index : integer := -1;
        variable led_count : integer := 0;

    begin
        result := (others => '0');

        -- Find the highest '1' bit
        for i in CHANNEL_LENGHT-1 downto 0 loop
            if level(i) = '1' then
                msb_index := i;
                exit;
            end if;
        end loop;

        -- Below 2^8: no LED
        if msb_index < 8 then
            led_count := 0;
        else
            led_count := msb_index - 7;
        end if;

        -- Limit led_count to NUM_LEDS
        if led_count > NUM_LEDS then
            led_count := NUM_LEDS;
        end if;

        -- Generate LED bar
        for i in 0 to NUM_LEDS-1 loop
            if i < led_count then
                result(i) := '1';
            end if;
        end loop;

        return result;
    end function;




---------------------PROCESS------------------------
begin

    s_axis_tready <= '1';
    led <= led_reg;

    process(aclk)
        variable current_abs : unsigned(CHANNEL_LENGHT-1 downto 0);
        variable sum_level   : unsigned(CHANNEL_LENGHT downto 0);
    begin
        if rising_edge(aclk) then

            if aresetn = '0' then
                refresh_counter <= 0;
                left_abs        <= (others => '0');
                avg_level       <= (others => '0');
                led_reg         <= (others => '0');

            else

                -- AXI Stream sample accepted
                if s_axis_tvalid = '1' then

                    current_abs := abs_sample(s_axis_tdata);

                    if s_axis_tlast = '0' then
            
                        left_abs <= current_abs;

                    else
                        sum_level := resize(left_abs, CHANNEL_LENGHT+1) +
                                     resize(current_abs, CHANNEL_LENGHT+1);

                        avg_level <= sum_level(CHANNEL_LENGHT downto 1);-- Average abs(left) and abs(right)

                    end if;

                end if;

                -- Refresh LED output every refresh_time_ms

                if refresh_counter = REFRESH_CYCLES-1 then
                    refresh_counter <= 0;
                    led_reg <= level_to_leds(avg_level);
                else
                    refresh_counter <= refresh_counter + 1;
                end if;

            end if;
        end if;
    end process;

end Behavioral;
