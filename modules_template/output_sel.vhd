library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity output_sel is
	Generic (
		TDATA_WIDTH		: positive := 24;		-- 3 byte for audio
		LED_WIDTH		: positive := 8;
        HIGHER_BOUND	: integer := 2**23-1;	-- Inclusive (max value of TDATA at 24 bit signed)
		LOWER_BOUND		: integer := -2**23		-- Inclusive (min value of TDATA at 24 bit signed)
	);
	Port (
		aclk			: in std_logic;
		aresetn			: in std_logic;

		s_axis_tvalid	: in std_logic;
		s_axis_tdata	: in std_logic_vector(TDATA_WIDTH-1 downto 0);
		s_axis_tlast	: in std_logic;
		s_axis_tready	: out std_logic;

		m_axis_tvalid	: out std_logic;
		m_axis_tdata	: out std_logic_vector(TDATA_WIDTH-1 downto 0);
		m_axis_tlast	: out std_logic;
		m_axis_tready	: in std_logic;

		toggle			: in std_logic;

        led_r			: out std_logic_vector(LED_WIDTH-1 downto 0);
		led_g			: out std_logic_vector(LED_WIDTH-1 downto 0);
		led_b			: out std_logic_vector(LED_WIDTH-1 downto 0)
	);
end entity output_sel;

architecture rtl of output_sel is

	type out_sel_type is (l_r,mute,l_l,r_r,lpr_lpr,lmr_lmr,lpr_lmr,lmr_lpr);

	signal out_sel : out_sel_type :=l_r;

begin

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
	
end architecture;
