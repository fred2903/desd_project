library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity effect_selector is
    Generic (
        JOYSTICK_LENGTH : integer := 10 -- 10 bit for X and Y axis
    );
    Port (
        clk : in std_logic;
        resetn : in std_logic;

        effect : in std_logic;
        jstck_x : in std_logic_vector(JOYSTICK_LENGTH-1 downto 0);
        jstck_y : in std_logic_vector(JOYSTICK_LENGTH-1 downto 0);

        volume : out std_logic_vector(JOYSTICK_LENGTH-1 downto 0);
        balance : out std_logic_vector(JOYSTICK_LENGTH-1 downto 0);
        gain : out std_logic_vector(JOYSTICK_LENGTH-1 downto 0);
        delay : out std_logic_vector(JOYSTICK_LENGTH-1 downto 0)
    );
end effect_selector;

architecture Behavioral of effect_selector is

    ---------- CONSTANTS ----------
    constant HALF_BAL_VOL : integer := 2**(JOYSTICK_LENGTH-1); -- half of the range for balance/volume
    -------------------------------

begin

    ---------- PROCESSES ----------
    process(clk)
    begin
        if rising_edge(clk) then
            if resetn = '0' then
                gain <= (others => '0');
                delay <= (others => '0');
                balance <= std_logic_vector(to_unsigned(HALF_BAL_VOL, JOYSTICK_LENGTH));
                volume <= std_logic_vector(to_unsigned(HALF_BAL_VOL, JOYSTICK_LENGTH));
            else
                if effect = '1' then
                    gain <= jstck_x;
                    delay <= jstck_y;
                else -- effect = '0'
                    balance <= jstck_x;
                    volume <= jstck_y;
                end if;
            end if;
        end if;
    end process;
    -------------------------------

end Behavioral;
