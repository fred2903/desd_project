library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity depacketizer is
    generic (
        TDATA_WIDTH : integer := 8;             -- UART is 1 byte
        HEADER : std_logic_vector := X"69";
        FOOTER : std_logic_vector := X"42";
        CLK_FREQ_HZ : integer := 100000000      -- Use this for remaining_minutes, remaining_seconds
    );
    port (
        aclk   : in std_logic;
        aresetn : in std_logic;

        s_axis_tvalid	: in std_logic;
		s_axis_tdata	: in std_logic_vector(TDATA_WIDTH-1 downto 0);
		s_axis_tready	: out std_logic;

        send_audio : out std_logic;
        remaining_minutes : out std_logic_vector(6 downto 0);   -- MIN is unsigned from 0 to 60 (5 bits) but the binary_to_decimal required 7 bits, keep the last bit at 0
        remaining_seconds : out std_logic_vector(6 downto 0)    -- MIN is unsigned from 0 to 59 (5 bits) but the binary_to_decimal required 7 bits, keep the last bit at 0
        
    );
end entity depacketizer;

architecture rtl of depacketizer is

begin

end architecture;
