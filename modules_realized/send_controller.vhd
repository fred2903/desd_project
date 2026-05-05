library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity send_controller is
    generic(
        DATA_LENGTH  : positive := 16   -- 2 byte of TDATA in FLOAT COMPRESSOR
    );
    port (
        aclk   : in std_logic;
        aresetn : in std_logic;

        s_axis_tvalid	: in std_logic;
        s_axis_tdata	: in std_logic_vector(DATA_LENGTH-1 downto 0);
        s_axis_tlast    : in std_logic;
        s_axis_tready	: out std_logic;

        m_axis_tvalid	: out std_logic;
        m_axis_tdata	: out std_logic_vector(DATA_LENGTH-1 downto 0);
        m_axis_tready	: in std_logic;

        send_audio    : in std_logic
    );
end entity send_controller;

architecture rtl of send_controller is
    --FSM
    type AXI_STATE_TYPE is (WAIT_LEFT, WAIT_RIGHT, SEND_LEFT, SEND_RIGHT);
    signal AXI_STATE          : AXI_STATE_TYPE;
    --REG
    signal data_left, data_right : std_logic_vector(DATA_LENGTH-1 downto 0) := (others => '0');
begin

    with AXI_STATE select m_axis_tvalid <=
        '1' when SEND_LEFT,
        '1' when SEND_RIGHT,
        '0' when others;

    with AXI_STATE select s_axis_tready <=
        '1' when WAIT_LEFT,
        '1' when WAIT_RIGHT,
        '0' when others;

    with AXI_STATE select m_axis_tdata <=
        data_left             when SEND_LEFT,
        data_right            when SEND_RIGHT,
        (others => '-')       when others;

    process (aclk)
    begin
        if rising_edge(aclk) then
            if aresetn = '0' then

                AXI_STATE      <= WAIT_LEFT;
                data_left      <= (others => '0');
                data_right     <= (others => '0');

            else

                case AXI_STATE is
                    when WAIT_LEFT =>
                        if s_axis_tvalid = '1' and send_audio = '1' then
                            if  s_axis_tlast = '0' then
                                data_left  <= s_axis_tdata;
                                AXI_STATE  <= WAIT_RIGHT;
                            else
                                AXI_STATE     <= WAIT_LEFT;
                            end if;
                        end if;

                    when WAIT_RIGHT =>
                        if s_axis_tvalid = '1' and send_audio = '1' then
                            if  s_axis_tlast = '1' then
                                data_right  <= s_axis_tdata;
                                AXI_STATE  <= SEND_LEFT;
                            else
                                AXI_STATE     <= WAIT_LEFT;
                            end if;
                        end if;

                    when SEND_LEFT =>
                        if m_axis_tready = '1' then
                            AXI_STATE     <= SEND_RIGHT;
                        end if;

                    when SEND_RIGHT =>
                        if m_axis_tready = '1' then
                            AXI_STATE     <= WAIT_LEFT;
                        end if;

                end case;
            end if;
        end if;
    end process;

end rtl;