library ieee;
use ieee.std_logic_1164.all;

entity send_controller is
    Generic (
        DATA_LENGHT : positive := 16 -- 2 byte of TDATA in FLOAT COMPRESSOR
    );
    Port (
        aclk : in std_logic;
        aresetn : in std_logic;

        s_axis_tvalid : in std_logic;
        s_axis_tdata : in std_logic_vector(DATA_LENGHT-1 downto 0);
        s_axis_tlast : in std_logic;
        s_axis_tready : out std_logic;

        m_axis_tvalid : out std_logic;
        m_axis_tdata : out std_logic_vector(DATA_LENGHT-1 downto 0);
        m_axis_tready : in std_logic;

        send_audio : in std_logic
    );
end entity send_controller;

architecture rtl of send_controller is

    ---------- TYPES ----------
    type state_type is (DISCARD, FORWARD);
    ---------------------------
    
    ---------- SIGNALS ----------
    signal state : state_type := DISCARD;
    -----------------------------

begin

    ---------- AXI4-STREAM OUTPUT FSM ----------
    with state select s_axis_tready <=
        m_axis_tready when FORWARD,
        '1' when DISCARD; -- Always ready to consume and drop data

    with state select m_axis_tvalid <=
        s_axis_tvalid when FORWARD,
        '0' when DISCARD; -- Prevent downstream from reading discarded data

    with state select m_axis_tdata <=
        s_axis_tdata when FORWARD,
        (others => '-') when DISCARD;
    --------------------------------------------

    ---------- PROCESSES ----------
    process (aclk)
    begin
        if rising_edge(aclk) then
            if aresetn = '0' then
                state <= DISCARD;
            else
                case state is
                    
                    -- Wait for upstream tvalid and tlast high, then check if send_audio requires to move to FORWARD state
                    when DISCARD =>
                        -- Wait until the end of the current packet before checking if the next packet should be forwarded
                        if s_axis_tvalid = '1' and s_axis_tlast = '1' then
                            if send_audio = '1' then
                                state <= FORWARD;
                            end if;
                        end if;

                    -- Wait for upstream tvalid and tlast high, and for downstream tready high, then check if send_audio requires to move to DISCARD state
                    when FORWARD =>
                        -- Wait until the end of the current packet before checking if the next packet should be discarded
                        if s_axis_tvalid = '1' and s_axis_tlast = '1' and m_axis_tready = '1' then
                            if send_audio = '0' then
                                state <= DISCARD;
                            end if;
                        end if;

                end case;
            end if;
        end if;
    end process;
    -------------------------------

end rtl;
