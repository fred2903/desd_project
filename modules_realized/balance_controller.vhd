library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity balance_controller is
	Generic (
		TDATA_WIDTH : positive := 24; -- Audio, 3 bytes
		BALANCE_WIDTH : positive := 10;
		BALANCE_STEP_2 : positive := 6 -- i.e., balance_values_per_step = 2**VOLUME_STEP_2
	);
	Port (
		aclk : in std_logic;
		aresetn : in std_logic;

		s_axis_tvalid : in std_logic;
		s_axis_tdata : in std_logic_vector(TDATA_WIDTH-1 downto 0);
		s_axis_tready : out std_logic;
		s_axis_tlast : in std_logic;

		m_axis_tvalid : out std_logic;
		m_axis_tdata : out std_logic_vector(TDATA_WIDTH-1 downto 0);
		m_axis_tready : in std_logic;
		m_axis_tlast : out std_logic;

		balance : in std_logic_vector(BALANCE_WIDTH-1 downto 0)
	);
end balance_controller;

architecture Behavioral of balance_controller is

	---------- CONSTANTS ----------
    constant HALF_BAL : integer := 2**(BALANCE_WIDTH-1);
    -------------------------------

	---------- TYPES ----------
	type state_type is (WAIT_DATA, COMPUTE, SEND_DATA);
	---------------------------
	
	---------- SIGNALS ----------
    signal reg_data : signed(TDATA_WIDTH-1 downto 0);
    signal reg_last : std_logic;
	signal reg_balance : std_logic_vector(BALANCE_WIDTH-1 downto 0);
	signal state : state_type := WAIT_DATA;
    signal processed_data : std_logic_vector(TDATA_WIDTH-1 downto 0);
	-----------------------------

begin

	---------- AXI4-STREAM OUTPUT FSM ----------
    with state select s_axis_tready <=
        '1' when WAIT_DATA, 
        '0' when others;

    with state select m_axis_tvalid <=
        '1' when SEND_DATA, 
        '0' when others;

    with state select m_axis_tdata <=
        processed_data when SEND_DATA,
        (others => '-') when others;

    with state select m_axis_tlast <=
        reg_last when SEND_DATA,
        '0' when others;
    --------------------------------------------

	---------- PROCESSES ----------
	process (aclk)
        variable delta_balance : signed(BALANCE_WIDTH downto 0); -- BALANCE_WIDTH instead of BALANCE_WIDTH-1 bits to safely perform subtraction without overflow risk
        variable exponent : integer;
        variable shifted_data : signed(TDATA_WIDTH-1 downto 0);
    begin
        if rising_edge(aclk) then
            if aresetn = '0' then
                state <= WAIT_DATA;
            else
                case state is

                    -- Wait for upstream tvalid high, then capture input data and move to COMPUTE state
                    when WAIT_DATA =>
                        if s_axis_tvalid = '1' then
                            reg_data <= signed(s_axis_tdata);
                            reg_last <= s_axis_tlast; -- 0: left, 1: right
                            reg_balance <= balance; -- Buffer the balance here for stability
                            state <= COMPUTE;
                        end if;

                    -- Apply attenuation based on balance signal and channel, then move to SEND_DATA state
                    when COMPUTE =>
                        -- Calculate shift amount
                        delta_balance := signed('0'&reg_balance) - HALF_BAL;
                        exponent := to_integer(shift_right(delta_balance, BALANCE_STEP_2));
						shifted_data := reg_data;

						-- Apply shift if the channel matches the direction of the balance adjustment
                        -- Right moves decrease left volume
                        if reg_last = '0' and exponent > 0 then
                            shifted_data := shift_right(shifted_data, exponent);
                        -- Left moves decrease right volume
						elsif reg_last = '1' and exponent < 0 then
                            shifted_data := shift_right(shifted_data, -exponent);
                        end if;

						-- Clipping isn't required since shifting right will not cause overflow, in the worst case the channel volume will be completely attenuated to 0
                        processed_data <= std_logic_vector(shifted_data);

                        state <= SEND_DATA;

                    -- Wait for downstream tready high, then move back to WAIT_DATA state to process the next sample
                    when SEND_DATA =>
                        if m_axis_tready = '1' then
                            state <= WAIT_DATA;
                        end if;

                end case;
            end if;
        end if;
    end process;
	-------------------------------

end Behavioral;
