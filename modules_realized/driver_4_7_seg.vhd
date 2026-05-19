library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity driver_4_7seg is
    Generic (
        MUX_TIME_MS: positive := 1; -- multiplexin time between digit, switch to one digit to another every MUX_TIME_MS
        CLOCK_PERIOD_NS: positive := 10 -- time base
    );
    Port ( 
    	clk : in std_logic;
        resetn: in std_logic;

        num1, num2, num3, num4: in std_logic_vector(3 downto 0);

        an: out std_logic_vector(3 downto 0);
        seg: out std_logic_vector(0 to 6);
        dp: out std_logic
    );
end driver_4_7seg;

architecture Behavioral of driver_4_7seg is

    ---------- CONSTANTS ----------
    constant MUX_CYCLES : integer := (MUX_TIME_MS * 1_000_000) / CLOCK_PERIOD_NS;
    -------------------------------

    ---------- TYPES ----------
    type state_type is (DIGIT1, DIGIT2, DIGIT3, DIGIT4);
    ---------------------------

    ---------- SIGNALS ----------
    signal num: std_logic_vector(3 downto 0);
    signal seg_s: std_logic_vector(0 to 6);
    signal state : state_type := DIGIT1;
    signal timer_cnt : integer range 0 to MUX_CYCLES-1 := 0;
    -----------------------------

begin
    
    ---------- SEGMENT SIGNAL DECODER ----------
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
    ----------------------------------------

    ---------- DIGIT MULTIPLEXING OUTPUT FSM ----------
    -- Select which 4-bit nibble to route to the decoder matrix based on the current active digit
    with state select num <=
        num1 when DIGIT1,
        num2 when DIGIT2,
        num3 when DIGIT3,
        num4 when DIGIT4;

    -- Only an anode is pulled to '0' at a time to turn on the corresponding digit
    with state select an <=
        "1110" when DIGIT1,
        "1101" when DIGIT2,
        "1011" when DIGIT3,
        "0111" when DIGIT4;
    ---------------------------------------------------

    ---------- DATA FLOW ----------
    seg <= seg_s;
    dp <= '1'; -- "dot" is not used, always off
    -------------------------------

    ---------- PROCESSES ----------
    process (clk)
    begin
        if rising_edge(clk) then
            if resetn = '0' then
                state <= DIGIT1;
                timer_cnt <= 0;
            else
                -- Multiplexing timer and state update logic (runs every MUX_CYCLES)
                if timer_cnt = MUX_CYCLES-1 then
                    timer_cnt <= 0;
                    
                    -- Cycle to the next sequential display element
                    case state is

                        when DIGIT1 =>
                        
                            state <= DIGIT2;

                        when DIGIT2 =>
                        
                            state <= DIGIT3;
                        
                        when DIGIT3 =>
                        
                            state <= DIGIT4;
                        
                        when DIGIT4 =>
                        
                            state <= DIGIT1;
                        
                    end case;
                else
                    timer_cnt <= timer_cnt + 1;
                end if;
            end if;
        end if;
    end process;
    -------------------------------

end Behavioral;
