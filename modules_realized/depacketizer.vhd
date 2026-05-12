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
        aclk    : in std_logic;
        aresetn : in std_logic;

        s_axis_tvalid   : in std_logic;
        s_axis_tdata    : in std_logic_vector(TDATA_WIDTH-1 downto 0);
        s_axis_tready   : out std_logic;

        send_audio        : out std_logic;
        remaining_minutes : out std_logic_vector(6 downto 0);   -- MIN is unsigned from 0 to 60 (5(6?) bits) but the binary_to_decimal required 7 bits, keep the last bit at 0
        remaining_seconds : out std_logic_vector(6 downto 0)    -- MIN is unsigned from 0 to 60 (5(6?) bits) but the binary_to_decimal required 7 bits, keep the last bit at 0
    );
end entity depacketizer;

architecture rtl of depacketizer is
    
    -- FSM Signals
    type state_uart_type is (WAIT_HEADER, GET_MIN, GET_SEC, WAIT_FOOTER);
    signal state_uart       : state_uart_type;            
    signal reg_min, reg_sec : unsigned(6 downto 0);   
    signal packet_valid     : std_logic;

    -- Timing and Control Signals
    signal int_send_audio : std_logic;
    signal int_min        : integer range 0 to 60;
    signal int_sec        : integer range 0 to 59;
    signal tick_counter   : integer range 0 to CLK_FREQ_HZ - 1;

begin
    
    -- axi4-stream bit-rate is higher than uart, so it's fine to be always ready since there is no m_axis
    s_axis_tready <= '1';

    -------------------------------------------------------------------------
    -- PROCESS 1: UART FSM
    -------------------------------------------------------------------------
    process (aclk)
    begin
        if rising_edge(aclk) then
            if aresetn = '0' then
                state_uart   <= WAIT_HEADER;
                packet_valid <= '0';
                reg_min      <= (others => '0');
                reg_sec      <= (others => '0');
            else
                -- Default to '0', pulses high for 1 clock cycle on valid FOOTER
                packet_valid <= '0'; 

                case state_uart is
                    when WAIT_HEADER =>
                        if s_axis_tvalid = '1' then
                            if s_axis_tdata = HEADER then
                                state_uart <= GET_MIN;
                            else
                                state_uart <= WAIT_HEADER;
                            end if;
                        end if;

                    when GET_MIN =>
                        if s_axis_tvalid = '1' then
                            if unsigned(s_axis_tdata) <= 60 then
                                reg_min    <= unsigned(s_axis_tdata(6 downto 0));
                                state_uart <= GET_SEC;
                            else
                                state_uart <= WAIT_HEADER;
                            end if;
                        end if;

                    when GET_SEC =>
                        if s_axis_tvalid = '1' then
                            if unsigned(s_axis_tdata) < 60 then
                                reg_sec    <= unsigned(s_axis_tdata(6 downto 0));
                                state_uart <= WAIT_FOOTER;
                            else
                                state_uart <= WAIT_HEADER;
                            end if;
                        end if;

                    when WAIT_FOOTER =>
                        if s_axis_tvalid = '1' then
                            if s_axis_tdata = FOOTER then
                                packet_valid <= '1'; -- Signal the timing process
                            end if;
                            state_uart <= WAIT_HEADER; -- Always return to header
                        end if;

                    when others =>
                        state_uart <= WAIT_HEADER;

                end case;
            end if;
        end if;
    end process;

    -------------------------------------------------------------------------
    -- PROCESS 2: Timing, Countdown, and send_audio Logic
    -------------------------------------------------------------------------
    process (aclk)
    begin
        if rising_edge(aclk) then
            if aresetn = '0' then
                int_send_audio <= '0';
                int_min        <= 0;
                int_sec        <= 0;
                tick_counter   <= 0;
            else
                
                -- 1. Handle Commands (Valid Packets)
                if packet_valid = '1' then
                    if int_send_audio = '0' then
                        -- While NOT acquiring
                        if reg_min = 0 and reg_sec = 0 then
                            -- Ignore packet with MIN=0 and SEC=0
                        else
                            -- Start acquisition
                            int_send_audio <= '1';
                            int_min        <= to_integer(reg_min);
                            int_sec        <= to_integer(reg_sec);
                            tick_counter   <= 0;
                        end if;
                    else
                        -- While ALREADY acquiring
                        if reg_min = 0 and reg_sec = 0 then
                            -- Stop acquisition and clear countdown
                            int_send_audio <= '0';
                            int_min        <= 0;
                            int_sec        <= 0;
                        end if;
                    end if;
                end if;

                -- 2. Handle Countdown Routine (1 Hz Tick)
                if int_send_audio = '1' then
                    if tick_counter = CLK_FREQ_HZ - 1 then
                        tick_counter <= 0;

                        if int_sec > 0 then
                            int_sec <= int_sec - 1;
                            
                            -- Check for Natural End Trigger
                            if int_sec = 1 and int_min = 0 then
                                int_send_audio <= '0';
                            end if;
                            
                        elsif int_min > 0 then
                            int_min <= int_min - 1;
                            int_sec <= 59;
                        end if;

                    else
                        tick_counter <= tick_counter + 1;
                    end if;
                end if;
            end if;
        end if;
    end process;

    -------------------------------------------------------------------------
    -- Concurrent Output Assignments
    -------------------------------------------------------------------------
    send_audio        <= int_send_audio;
    remaining_minutes <= '0' & std_logic_vector(to_unsigned(int_min, 6));
    remaining_seconds <= '0' & std_logic_vector(to_unsigned(int_sec, 6));

end architecture;
