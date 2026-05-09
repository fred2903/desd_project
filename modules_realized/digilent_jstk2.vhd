library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity digilent_jstk2 is
	Generic (
		DELAY_US : integer := 25; -- CONSTANT DO NOT TOUCH
		CLKFREQ : integer := 100_000_000; -- Base time
		SPI_SCLKFREQ : integer := 66_666 -- Base time
	);
	Port ( 
		aclk : in STD_LOGIC;
		aresetn : in STD_LOGIC;

		m_axis_tvalid : out STD_LOGIC;
		m_axis_tdata : out STD_LOGIC_VECTOR(7 downto 0);
		m_axis_tready : in STD_LOGIC;

		s_axis_tvalid : in STD_LOGIC;
		s_axis_tdata : in STD_LOGIC_VECTOR(7 downto 0);

		jstk_x : out std_logic_vector(9 downto 0);
		jstk_y : out std_logic_vector(9 downto 0);
		btn_jstk : out std_logic;
		btn_trigger : out std_logic;

		led_r : in std_logic_vector(7 downto 0);
		led_g : in std_logic_vector(7 downto 0);
		led_b : in std_logic_vector(7 downto 0)
	);
end digilent_jstk2;

architecture Behavioral of digilent_jstk2 is

	---------- CONSTANTS ----------
    constant HEADER_TX : std_logic_vector(7 downto 0) := x"84"; -- Standard JSTK2 cmdSetLedRGB command header
    constant WAIT_CYCLES : integer := (CLKFREQ / 1_000_000) * DELAY_US; -- Number of clock cycles to wait for the required DELAY_US before the next command packet is initiated
	-------------------------------

    ---------- TYPES ----------
    type tx_state_type is (WAIT_DELAY, SEND_HEADER, SEND_RED, SEND_GREEN, SEND_BLUE);
    type rx_state_type is (GET_HEADER, GET_X, GET_Y, GET_BUTTONS);
	---------------------------

    ---------- SIGNALS ----------
    signal tx_state : tx_state_type := WAIT_DELAY;
    signal rx_state : rx_state_type := GET_HEADER;
    signal timer_cnt : integer range 0 to WAIT_CYCLES-1 := 0;
	-----------------------------

begin

	---------- AXI4-STREAM OUTPUT FSM ----------
    with tx_state select m_axis_tvalid <=
        '0' when WAIT_DELAY, 
        '1' when others;

    with tx_state select m_axis_tdata <=
        HEADER_TX when SEND_HEADER,
        led_r when SEND_RED,
        led_g when SEND_GREEN,
        led_b when SEND_BLUE,
        (others => '-') when others;
    --------------------------------------------

	---------- PROCESSES ----------
    -- Transmitter sends 4-byte packet [0x84, R, G, B]
    process (aclk)
    begin
        if rising_edge(aclk) then
            if aresetn = '0' then
                tx_state <= WAIT_DELAY;
                timer_cnt <= 0;
            else
                case tx_state is

					-- Wait for the required delay before sending the next packet
                    when WAIT_DELAY =>
                        if timer_cnt >= WAIT_CYCLES-1 then -- >= instead of = for safer comparison in case of any timing issues
                            timer_cnt <= 0;
                            tx_state <= SEND_HEADER;
                        else
                            timer_cnt <= timer_cnt + 1;
                        end if;

					-- Send the 4-byte packet sequentially, waiting for tready high before sending each byte
                    when SEND_HEADER =>
                        if m_axis_tready = '1' then
                            tx_state <= SEND_RED;
                        end if;

                    when SEND_RED =>
                        if m_axis_tready = '1' then
                            tx_state <= SEND_GREEN;
                        end if;

                    when SEND_GREEN =>
                        if m_axis_tready = '1' then
                            tx_state <= SEND_BLUE;
                        end if;

                    when SEND_BLUE =>
                        if m_axis_tready = '1' then
                            tx_state <= WAIT_DELAY;
                        end if;

                end case;
            end if;
        end if;
    end process;

    -- Receiver processes 4-byte packet [0xC0, X, Y, Buttons]
    process (aclk)
    begin
        if rising_edge(aclk) then
            if aresetn = '0' then
                rx_state <= GET_HEADER;
            else
                -- We consume data whenever tvalid is high (always ready)
                if s_axis_tvalid = '1' then
                    case rx_state is
                        
                        -- Process the 4-byte packet sequentially, waiting for tvalid high before processing each byte
                        when GET_HEADER =>
                            rx_state <= GET_X;

                        when GET_X =>
                            jstk_x <= s_axis_tdata&"00";
                            rx_state <= GET_Y;

                        when GET_Y =>
                            jstk_y <= s_axis_tdata&"00";
                            rx_state <= GET_BUTTONS;

                        when GET_BUTTONS =>
                            btn_jstk <= s_axis_tdata(0); 
                            btn_trigger <= s_axis_tdata(1); 
                            rx_state <= GET_HEADER;

                    end case;
                end if;
            end if;
        end if;
    end process;
	-------------------------------

end Behavioral;
