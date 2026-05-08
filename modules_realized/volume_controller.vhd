library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity volume_controller is
	Generic (
		TDATA_WIDTH : positive := 24;
		VOLUME_WIDTH : positive := 10;
		VOLUME_STEP_2 : positive := 6; -- i.e., volume_values_per_step = 2**VOLUME_STEP_2
		HIGHER_BOUND : integer := 2**23-1; -- Inclusive (max value of TDATA at 24 bit signed)
		LOWER_BOUND : integer := -2**23 -- Inclusive (min value of TDATA at 24 bit signed)
	);
	Port (
		aclk : in std_logic;
		aresetn : in std_logic;

		s_axis_tvalid : in std_logic;
		s_axis_tdata : in std_logic_vector(TDATA_WIDTH-1 downto 0);
		s_axis_tlast : in std_logic;
		s_axis_tready : out std_logic;

		m_axis_tvalid : out std_logic;
		m_axis_tdata : out std_logic_vector(TDATA_WIDTH-1 downto 0);
		m_axis_tlast : out std_logic;
		m_axis_tready : in std_logic;

		volume : in std_logic_vector(VOLUME_WIDTH-1 downto 0)
	);
end volume_controller;

architecture Behavioral of volume_controller is

	---------- CONSTANTS ----------
	constant HALF_VOL : integer := 2**(VOLUME_WIDTH-1);
	constant MAX_SHIFT : integer := HALF_VOL / (2**VOLUME_STEP_2);
	constant EXT_WIDTH : integer := TDATA_WIDTH + MAX_SHIFT;
	-------------------------------

	---------- TYPES ----------
	type state_type is (WAIT_DATA, COMPUTE, SEND_DATA);
	---------------------------

	---------- SIGNALS ----------
    signal reg_data : signed(TDATA_WIDTH-1 downto 0);
    signal reg_last : std_logic;
	signal reg_volume : std_logic_vector(VOLUME_WIDTH-1 downto 0);
	signal state : state_type := WAIT_DATA;
    signal processed_data : std_logic_vector(TDATA_WIDTH-1 downto 0);
	-----------------------------

	---------- FUNCTIONS ----------
    function clip_data(input_val : signed) return std_logic_vector is
    begin
        if input_val > to_signed(HIGHER_BOUND, input_val'length) then
            return std_logic_vector(to_signed(HIGHER_BOUND, TDATA_WIDTH));
        elsif input_val < to_signed(LOWER_BOUND, input_val'length) then
            return std_logic_vector(to_signed(LOWER_BOUND, TDATA_WIDTH));
        else
            return std_logic_vector(resize(input_val, TDATA_WIDTH));
        end if;
    end function;
    -------------------------------

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
		variable delta_volume : signed(VOLUME_WIDTH downto 0); -- VOLUME_WIDTH instead of VOLUME_WIDTH-1 bits to safely perform subtraction without overflow risk
    	variable exponent : integer;
        variable shifted_data : signed(EXT_WIDTH-1 downto 0); -- Buffer for shifting the volume-adjusted value, extended to accommodate potential overflow during shifting
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
                            reg_last <= s_axis_tlast;
							reg_volume <= volume; -- Buffer the volume here for stability
                            state <= COMPUTE;
                        end if;

                    -- Apply exponential gain and clip the output, then move to SEND_DATA state
                    when COMPUTE =>
                        -- Calculate shift amount
                        delta_volume := signed('0'&reg_volume) - HALF_VOL;
                        exponent := to_integer(shift_right(delta_volume, VOLUME_STEP_2));
                        
                        -- Apply shift (exponential gain)
                        shifted_data := resize(reg_data, shifted_data'length);
                        if exponent > 0 then
                            shifted_data := shift_left(shifted_data, exponent);
                        elsif exponent < 0 then
                            shifted_data := shift_right(shifted_data, -exponent);
                        end if;

                        -- Clipping (output saturation)
                        processed_data <= clip_data(shifted_data);
						
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
