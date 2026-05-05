library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VCNomponents.all;

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
    --FSM
    type FSM_DISPLAY_TYPE is (D1, D2, D3, D4);
    signal FSM_DISPLAY : FSM_DISPLAY_TYPE;
    --timing
    constant MAX_COUNT : integer := (mux_time_ms * 1_000_000) / clock_period_ns;
    signal timer_counter : integer range 0 to MAX_COUNT := 0;
    --reg
    signal num           : std_logic_vector(3 downto 0);
    signal seg_s         : STD_LOGIC_VECTOR(0 to 6);

begin

    -- =========================================================
    -- SEQUENTIAL PROCESS: Manages time and state transitions only
    -- =========================================================
    process(clk)
    begin
        if rising_edge(clk) then
            if resetn = '0' then
                timer_counter <= 0;
                FSM_DISPLAY   <= D1;
            else
                if timer_counter = MAX_COUNT - 1 then
                    timer_counter <= 0;
                    -- Simply move to the next state every 1 ms
                    case FSM_DISPLAY is
                        when D1 => FSM_DISPLAY <= D2;
                        when D2 => FSM_DISPLAY <= D3;
                        when D3 => FSM_DISPLAY <= D4;
                        when D4 => FSM_DISPLAY <= D1;
                    end case;
                else
                    timer_counter <= timer_counter + 1;
                end if;
            end if;
        end if;
    end process;

    -- =========================================================
    -- COMBINATIONAL PROCESS: Pure MUX based on current state
    -- =========================================================

    with FSM_DISPLAY select num <=
        num1  when D1,
        num2  when D2,
        num3  when D3,
        num4  when D4;

    with FSM_DISPLAY select an <=
        "1110"  when D1,
        "1101"  when D2,
        "1011"  when D3,
        "0111"  when D4;

    --or (more easy to read)

    --process(FSM_DISPLAY, num1, num2, num3, num4)
    --begin
    --    case FSM_DISPLAY is
    --        when D1 =>
    --            num <= num1;
    --            an  <= "1110"; -- Turns on the leftmost display
    --        when D2 =>
    --            num <= num2;
    --            an  <= "1101"; -- Turns on the second display from the left
    --        when D3 =>
    --            num <= num3;
    --            an  <= "1011"; -- Turns on the third display
    --        when D4 =>
    --            num <= num4;
    --            an  <= "0111"; -- Turns on the rightmost display
    --    end case;
    --end process;

    -- ===================================================
    -- 7-SEGMENT DECODER (Combinational)
    -- ========================================================
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

    dp <= '1'; -- Decimal point is ignored (kept OFF)
    seg <= seg_s;

end Behavioral;