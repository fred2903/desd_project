library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity output_sel is
	Generic (
		TDATA_WIDTH : positive := 24; -- 3 byte for audio
		LED_WIDTH : positive := 8;
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

		toggle : in std_logic;

        led_r : out std_logic_vector(LED_WIDTH-1 downto 0);
		led_g : out std_logic_vector(LED_WIDTH-1 downto 0);
		led_b : out std_logic_vector(LED_WIDTH-1 downto 0)
	);
end entity output_sel;

architecture Behavioral of output_sel is

	---------- TYPES ----------
	type out_sel_type is (l_r, mute, l_l, r_r, lpr_lpr, lmr_lmr, lpr_lmr, lmr_lpr);
	type state_type is (WAIT_LEFT_DATA, WAIT_RIGHT_DATA, COMPUTE, SEND_LEFT_DATA, SEND_RIGHT_DATA);
	---------------------------

	---------- SIGNALS ----------
	signal reg_left_data : signed(TDATA_WIDTH-1 downto 0);
    signal reg_right_data : signed(TDATA_WIDTH-1 downto 0);
	signal out_sel : out_sel_type := l_r;
	signal state : state_type := WAIT_LEFT_DATA;
    signal processed_left_data : std_logic_vector(TDATA_WIDTH-1 downto 0);
    signal processed_right_data : std_logic_vector(TDATA_WIDTH-1 downto 0);
	-----------------------------

	---------- FUNCTIONS ----------
	-- Function to clip the output data to the valid range [LOWER_BOUND, HIGHER_BOUND] of signed 24-bit audio
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
        '1' when WAIT_LEFT_DATA | WAIT_RIGHT_DATA,
        '0' when others;

    with state select m_axis_tvalid <=
        '1' when SEND_LEFT_DATA | SEND_RIGHT_DATA,
        '0' when others;

    with state select m_axis_tdata <=
        processed_left_data when SEND_LEFT_DATA,
        processed_right_data when SEND_RIGHT_DATA,
        (others => '-') when others;

    with state select m_axis_tlast <=
        '0' when SEND_LEFT_DATA,
		'1' when SEND_RIGHT_DATA,
        '0' when others;
    --------------------------------------------

	---------- LEDS OUTPUT FSM ----------
	with out_sel select led_r <= 
		(others => '1') when l_r,
		(others => '1') when mute,
		(others => '1') when l_l,
		(others => '1') when r_r,
		(others => '0') when lpr_lpr,
		(others => '0') when lmr_lmr,
		(others => '0') when lpr_lmr,
		(others => '0') when lmr_lpr;

	with out_sel select led_g <= 
		(others => '1') when l_r,
		(others => '1') when mute,
		(others => '0') when l_l,
		(others => '0') when r_r,
		(others => '1') when lpr_lpr,
		(others => '1') when lmr_lmr,
		(others => '0') when lpr_lmr,
		(others => '0') when lmr_lpr;

	with out_sel select led_b <= 
		(others => '1') when l_r,
		(others => '0') when mute,
		(others => '1') when l_l,
		(others => '0') when r_r,
		(others => '1') when lpr_lpr,
		(others => '0') when lmr_lmr,
		(others => '1') when lpr_lmr,
		(others => '0') when lmr_lpr;
	-------------------------------------

	---------- PROCESSES ----------
	process (aclk)
		variable sum_lr : signed(TDATA_WIDTH downto 0); -- TDATA_WIDTH instead of TDATA_WIDTH-1 to safely perform addition without overflow risk
        variable diff_lr : signed(TDATA_WIDTH downto 0); -- TDATA_WIDTH instead of TDATA_WIDTH-1 to safely perform subtraction without overflow risk
	begin
		if (rising_edge(aclk)) then
			if aresetn = '0' then
            	state <= WAIT_LEFT_DATA;
            	out_sel <= l_r;
			else

				-- Change out_sel when toggle signal is active with a cyclic order
                if toggle = '1' then
                    if out_sel = out_sel_type'high then
    					out_sel <= out_sel_type'low;
					else
    					out_sel <= out_sel_type'val(out_sel_type'pos(out_sel) + 1);
					end if;
                end if;

				-- Audio processing depending on out_sel
                case state is

                    -- Wait for upstream tvalid high and tlast low, then capture input left data and move to WAIT_RIGHT_DATA state
                    when WAIT_LEFT_DATA =>
                        if s_axis_tvalid = '1' and s_axis_tlast = '0' then
                            reg_left_data <= signed(s_axis_tdata);
                            state <= WAIT_RIGHT_DATA;
                        end if;

                    -- Wait for upstream tvalid high and tlast high, then capture input right data and move to COMPUTE state
                    when WAIT_RIGHT_DATA =>
                        if s_axis_tvalid = '1' and s_axis_tlast = '1' then
                            reg_right_data <= signed(s_axis_tdata);
                            state <= COMPUTE;
						elsif s_axis_tvalid = '1' and s_axis_tlast = '0' then -- If a new left sample arrives before a right sample, capture it immediately as self healing mechanism and stay in WAIT_RIGHT_DATA state
							reg_left_data <= signed(s_axis_tdata);
                        end if;

					-- Perform the selected output processing based on out_sel, then move to SEND_LEFT_DATA state to output the left sample
                    when COMPUTE =>
						-- Pre-calculate sum and difference between left and right samples to simplify the following calculations
                        sum_lr := resize(reg_left_data, TDATA_WIDTH+1) + resize(reg_right_data, TDATA_WIDTH+1);
                        diff_lr := resize(reg_left_data, TDATA_WIDTH+1) - resize(reg_right_data, TDATA_WIDTH+1);
                        
						-- Perform different calculations based on out_sel
						case out_sel is
                            when l_r =>
								processed_left_data <= std_logic_vector(reg_left_data);
								processed_right_data <= std_logic_vector(reg_right_data);
                            when mute =>
								processed_left_data <= (others => '0');
								processed_right_data <= (others => '0');
                            when l_l =>
								processed_left_data <= std_logic_vector(reg_left_data);
								processed_right_data <= std_logic_vector(reg_left_data);
                            when r_r =>
								processed_left_data <= std_logic_vector(reg_right_data);
								processed_right_data <= std_logic_vector(reg_right_data);
                            when lpr_lpr =>
								processed_left_data <= clip_data(sum_lr);
								processed_right_data <= clip_data(sum_lr);
                            when lmr_lmr =>
								processed_left_data <= clip_data(diff_lr);
								processed_right_data <= clip_data(diff_lr);
                            when lpr_lmr =>
								processed_left_data <= clip_data(sum_lr);
								processed_right_data <= clip_data(diff_lr);
                            when lmr_lpr =>
								processed_left_data <= clip_data(diff_lr);
								processed_right_data <= clip_data(sum_lr);
                        end case;

                        state <= SEND_LEFT_DATA;

                    -- Wait for downstream tready high, then move to SEND_RIGHT_DATA state to output the right sample
                    when SEND_LEFT_DATA =>
                        if m_axis_tready = '1' then
                            state <= SEND_RIGHT_DATA;
                        end if;

                    -- Wait for downstream tready high, then move back to WAIT_LEFT_DATA state
                    when SEND_RIGHT_DATA =>
                        if m_axis_tready = '1' then
                            state <= WAIT_LEFT_DATA;
                        end if;
				
                end case;

			end if;
		end if;
	end process;
	-------------------------------
	
end architecture;
