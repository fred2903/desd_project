library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity binary_to_decimal is
    Port (
        clk : in std_logic;

        binary_num : in std_logic_vector(6 downto 0);

        decade_digit : out std_logic_vector(3 downto 0);
        unit_digit : out std_logic_vector(3 downto 0)  
    );
end entity binary_to_decimal;

architecture rtl of binary_to_decimal is

begin

    process(clk)
        variable bin_int : integer range 0 to 127;
        variable decade : integer range 0 to 9;
        variable unit : integer range 0 to 9;
    begin
        if rising_edge(clk) then
            -- Convert the 7-bit binary input to an integer for easier manipulation
            bin_int := to_integer(unsigned(binary_num));

            -- Clamp the input to 99 to fit into two decimal digits
            if bin_int > 99 then
                decade := 9;
                unit := 9;
            else
                -- Division and modulo by constants and within small ranges can be automatically synthesized efficiently
                decade := bin_int / 10;
                unit := bin_int mod 10;
            end if;

            -- Convert the resulting integer digits back to 4-bit std_logic_vector
            decade_digit <= std_logic_vector(to_unsigned(decade, 4));
            unit_digit <= std_logic_vector(to_unsigned(unit, 4));
        end if;
    end process;

end architecture;
