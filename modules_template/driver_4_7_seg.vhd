
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity driver_4_7seg is
    Generic(
        mux_time_ms: positive:=1;       -- multiplexin time between digit, switch to one digit to another every mux_time_ms
        clock_period_ns: positive :=10  -- time base
    );
    Port ( 
    	clk : in STD_LOGIC;
        resetn: in STD_LOGIC;
        num1, num2, num3, num4: in STD_LOGIC_VECTOR(3 downto 0);
        an: out STD_LOGIC_VECTOR(3 downto 0);
        seg: out STD_LOGIC_VECTOR(0 to 6);
        dp: out STD_LOGIC
        );
end driver_4_7seg;

architecture Behavioral of driver_4_7seg is

    signal num: std_logic_vector(3 downto 0);
    signal seg_s: STD_LOGIC_VECTOR(0 to 6);

begin
    with num select seg_s <=
        "0000001" when "0000",
        "1001111" when "0001",
        "0010010" when "0010",
        "0000110" when "0011",
        "1001100" when "0100",
        "0100100" when "0101",
        "0100000" when "0110",
        "0001111" when "0111",
        "0000000" when "1000",
        "0000100" when "1001",
        "0001000" when "1010",
        "1100000" when "1011",
        "0110001" when "1100",
        "1000010" when "1101",
        "0110000" when "1110",
        "0111000" when "1111",
        "1111111" when others;

end Behavioral;
