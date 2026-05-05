--binary to decimal without division, algorithm <<shift and add 3>>
--https://www.youtube.com/watch?v=IBgiB7KXfEY

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

    --FSM
    type state_type is (IDLE, SHIFT, CHECK, DONE);
    signal state : state_type;
    --reg
    signal hundred_digit   :   std_logic_vector(3 downto 0);    -- just is case since binary_num is 7 bit
    signal counter : integer range 0 to binary_num'high;      --the algorith is over when (binary_num'lenght) shift has occured
    -- shift_reg contain (hundred_digit,decade_digit,unit_digit,binary_num) to perform the shifts in a easy way
    signal shift_reg   :   unsigned(binary_num'length + hundred_digit'length + decade_digit'length + unit_digit'length -1 downto 0);
    
begin
    
process(clk)
variable shift_var :   unsigned(binary_num'length + hundred_digit'length + decade_digit'length + unit_digit'length -1 downto 0);
    begin
        if rising_edge(clk) then
            case( state ) is
            
                when IDLE =>
                    shift_reg <= to_unsigned(0, shift_reg'length - binary_num'length) & unsigned(binary_num);
                    counter <= 0;
                    
                    state <= CHECK; 

                when CHECK =>
                    shift_var := shift_reg;
                    for i in 0 to 2 loop
                        if shift_var(shift_var'high - i*4 downto shift_var'high - 3 -i*4) > 4 then
                            shift_var(shift_var'high - i*4 downto shift_var'high - 3 -i*4) := shift_var(shift_var'high - i*4 downto shift_var'high - 3 -i*4) + 3;
                        end if ;
                    end loop;  
                    shift_reg <= shift_var;
                    state <= SHIFT;

                when SHIFT =>
                    shift_reg <= shift_reg(shift_reg'high - 1 downto 0) & '0';
                    if counter = binary_num'high then
                        state <= DONE;
                    else
                        counter <= counter + 1;
                        state <= CHECK;
                    end if ;

                when DONE =>
                    unit_digit <= std_logic_vector(shift_reg(binary_num'length +3 downto binary_num'length));
                    decade_digit <= std_logic_vector(shift_reg(binary_num'length +3 + 4 downto binary_num'length + 4));
                    hundred_digit <= std_logic_vector(shift_reg(binary_num'length +3 + 8 downto binary_num'length + 8));
                    state <= IDLE;

                when others =>
                    state <= IDLE;

            end case ;
        end if ;
    end process;
end architecture;