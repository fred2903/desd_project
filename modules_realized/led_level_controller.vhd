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

    -- refresh counter max value
    constant REFRESH_COUNT_MAX : integer :=
        (refresh_time_ms * 1_000_000) / clock_period_ns;

    -- FSM states
    type state_t is (
        IDLE,
        WAIT_REFRESH,
        UPDATE_LED
    );

    signal state : state_t;

    -- absolute value of left/right channels
    signal left_abs  : unsigned(CHANNEL_LENGHT-1 downto 0);
    signal right_abs : unsigned(CHANNEL_LENGHT-1 downto 0);

    -- peak detector
    signal peak_level : unsigned(CHANNEL_LENGHT-1 downto 0);

    -- number of active LEDs
    signal led_level : integer range 0 to NUM_LEDS;

    -- refresh counter
    signal refresh_counter :
        integer range 0 to REFRESH_COUNT_MAX;

begin

    -- AXIS always ready
    s_axis_tready <= '1';

    process(aclk)

        -- signed audio sample
        variable sample_signed :
            signed(CHANNEL_LENGHT-1 downto 0);

        -- absolute value of sample
        variable sample_abs :
            unsigned(CHANNEL_LENGHT-1 downto 0);

        -- average audio level
        variable avg_tmp :
            unsigned(CHANNEL_LENGHT-1 downto 0);

        -- mapped LED level
        variable new_level :
            integer range 0 to NUM_LEDS;

    begin

        if rising_edge(aclk) then

            if aresetn = '0' then

                -- reset FSM
                state <= IDLE;

                -- clear audio registers
                left_abs <= (others => '0');
                right_abs <= (others => '0');

                -- clear peak detector
                peak_level <= (others => '0');

                -- clear LED level
                led_level <= 0;

                -- clear counter
                refresh_counter <= 0;

            else

                -- receive audio sample
                if s_axis_tvalid = '1' then

                    -- convert input sample to signed
                    sample_signed := signed(s_axis_tdata);

                    -- absolute value
                    if sample_signed < 0 then
                        sample_abs := unsigned(-sample_signed);
                    else
                        sample_abs := unsigned(sample_signed);
                    end if;

                    -- stereo extraction
                    -- tlast = 0 -> left
                    -- tlast = 1 -> right
                    if s_axis_tlast = '0' then
                        left_abs <= sample_abs;
                    else
                        right_abs <= sample_abs;
                    end if;

                    -- average left/right level
                    avg_tmp := (left_abs + right_abs) srl 1;

                    -- peak detector
                    if avg_tmp > peak_level then
                        peak_level <= avg_tmp;
                    end if;

                end if;

                case state is

                    when IDLE =>

                        refresh_counter <= 0;

                        state <= WAIT_REFRESH;

                    when WAIT_REFRESH =>

                        -- wait refresh period
                        if refresh_counter =
                            REFRESH_COUNT_MAX-1 then

                            refresh_counter <= 0;

                            state <= UPDATE_LED;

                        else

                            refresh_counter <=
                                refresh_counter + 1;

                        end if;

                    when UPDATE_LED =>

                        -- map audio amplitude to LEDs
                        new_level :=
                            to_integer(
                                peak_level(
                                    CHANNEL_LENGHT-1 downto
                                    CHANNEL_LENGHT-4
                                )
                            );

                        -- VU meter effect:fast attack, slow decay
                      
                        if new_level > led_level then

                            led_level <= new_level;

                        elsif led_level > 0 then

                            led_level <= led_level - 1;

                        end if;

                        -- clear peak detector
                        peak_level <= (others => '0');

                        state <= WAIT_REFRESH;

                end case;

            end if;

        end if;

    end process;

    -- LED bar generation
    process(all)
    begin

        led <= (others => '0');

        for i in 0 to NUM_LEDS-1 loop

            if i < led_level then
                led(i) <= '1';
            end if;

        end loop;

    end process;

end Behavioral;
