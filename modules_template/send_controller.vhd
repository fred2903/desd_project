library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity send_controller is
    generic(
        DATA_LENGHT  : positive := 16   -- 2 byte of TDATA in FLOAT COMPRESSOR
    );
    port (
        aclk   : in std_logic;
        aresetn : in std_logic;

        s_axis_tvalid	: in std_logic;
        s_axis_tdata	: in std_logic_vector(DATA_LENGHT-1 downto 0);
        s_axis_tlast    : in std_logic;
        s_axis_tready	: out std_logic;

        m_axis_tvalid	: out std_logic;
        m_axis_tdata	: out std_logic_vector(DATA_LENGHT-1 downto 0);
        m_axis_tready	: in std_logic;

        send_audio    : in std_logic
    );
end entity send_controller;

architecture rtl of send_controller is

begin

end rtl;
