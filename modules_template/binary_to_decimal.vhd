library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity binary_to_decimal is
    port (
        clk   : in std_logic;

        binary_num : in std_logic_vector(6 downto 0);

        decade_digit : out std_logic_vector(3 downto 0);
        unit_digit : out std_logic_vector(3 downto 0)
        
    );
end entity binary_to_decimal;

architecture rtl of binary_to_decimal is

begin

end architecture;
