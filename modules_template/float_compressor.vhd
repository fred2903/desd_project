library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity float_compressor is
    generic(
        CHANNEL_LENGHT  : positive := 24;   -- 3 Byte for AXIS audio I2S
        OUTPUT_LENGHT  : positive := 16;    -- 2 Byte for float compression
        EXPONENT_LENGTH : POSITIVE := 4
    );
    port (
        aclk   : in std_logic;
        aresetn : in std_logic;

        s_axis_tvalid	: in std_logic;
        s_axis_tdata	: in std_logic_vector(CHANNEL_LENGHT-1 downto 0);
        s_axis_tlast    : in std_logic;
        s_axis_tready	: out std_logic;

        m_axis_tvalid	: out std_logic;
        m_axis_tdata	: out std_logic_vector(OUTPUT_LENGHT-1 downto 0);
        m_axis_tlast	: out std_logic;
        m_axis_tready	: in std_logic

    );
end entity float_compressor;

architecture rtl of float_compressor is

begin

end architecture;
