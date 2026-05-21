library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity depacketizer is
    Generic (
        TDATA_WIDTH : integer := 8; -- UART is 1 byte
        HEADER : std_logic_vector := x"69";
        FOOTER : std_logic_vector := x"42";
        CLK_FREQ_HZ : integer := 100_000_000 -- Use this for remaining_minutes, remaining_seconds
    );
    Port (
        aclk : in std_logic;
        aresetn : in std_logic;

        s_axis_tvalid : in std_logic;
		s_axis_tdata : in std_logic_vector(TDATA_WIDTH-1 downto 0);
		s_axis_tready : out std_logic;

        send_audio : out std_logic;
        remaining_minutes : out std_logic_vector(6 downto 0); -- MIN is unsigned from 0 to 60 (6 bits) but the binary_to_decimal required 7 bits, keep the last bit at 0
        remaining_seconds : out std_logic_vector(6 downto 0) -- MIN is unsigned from 0 to 59 (6 bits) but the binary_to_decimal required 7 bits, keep the last bit at 0
    );
end entity depacketizer;

architecture rtl of depacketizer is

    ---------- TYPES ----------
    type state_type is (WAIT_HEADER, GET_MIN, GET_SEC, WAIT_FOOTER);
    ---------------------------

    ---------- SIGNALS ----------
    signal reg_send_audio : std_logic := '0';
    signal reg_min : unsigned(5 downto 0) := (others => '0');
    signal reg_sec : unsigned(5 downto 0) := (others => '0');
    signal state : state_type := WAIT_HEADER;
    signal temp_min : unsigned(TDATA_WIDTH-1 downto 0);
    signal temp_sec : unsigned(TDATA_WIDTH-1 downto 0);
    signal tick_cnt : integer range 0 to CLK_FREQ_HZ-1 := 0; -- Timer for 1-second ticks
    -----------------------------

begin

    ---------- DATA FLOW ----------
    send_audio <= reg_send_audio;
    remaining_minutes <= '0' & std_logic_vector(reg_min);
    remaining_seconds <= '0' & std_logic_vector(reg_sec);
    -------------------------------

    ---------- PROCESSES ----------
    process (aclk)
    begin
        if rising_edge(aclk) then
            if aresetn = '0' then
                state <= WAIT_HEADER;
                s_axis_tready <= '0';
                reg_send_audio <= '0';
                reg_min <= (others => '0');
                reg_sec <= (others => '0');
                tick_cnt <= 0;
            else
                -- Always ready to accept packets (AXI4 Stream baud rate is quite higher than UART baud rate), except when reset is active
                s_axis_tready <= '1';

                -- Countdown timer and 1-second tick timer logic
                if reg_send_audio = '1' then -- Only run the timer when acquisition is active
                    if tick_cnt = CLK_FREQ_HZ-1 then
                        tick_cnt <= 0;

                        -- 1 second has passed, decrement the countdown timer
                        if reg_sec = 0 then
                            if reg_min > 0 then
                                reg_min <= reg_min - 1;
                                reg_sec <= to_unsigned(59, 6);
                            end if;
                        else
                            reg_sec <= reg_sec - 1;
                            
                            -- To stop the acquisition precisely when the timer reaches 00:00, the evaluation is performed at reg_min = 0 and reg_sec = 1, so it turns off immediately as reg_sec hits 0
                            if reg_min = 0 and reg_sec = 1 then
                                reg_send_audio <= '0';
                            end if;
                        end if;
                    else
                        tick_cnt <= tick_cnt + 1;
                    end if;
                else
                    tick_cnt <= 0; -- Keep 1-second tick timer cleared while acquisition is stopped
                end if;

                -- Packet decoder
                if s_axis_tvalid = '1' then
                    case state is
                        
                        -- Process the 4-byte packet sequentially, waiting for tvalid high before processing each byte
                        when WAIT_HEADER =>
                            if s_axis_tdata = HEADER then
                                state <= GET_MIN;
                            end if;

                        when GET_MIN =>
                            temp_min <= unsigned(s_axis_tdata);
                            state <= GET_SEC;

                        when GET_SEC =>
                            temp_sec <= unsigned(s_axis_tdata);
                            state <= WAIT_FOOTER;

                        when WAIT_FOOTER =>
                            if s_axis_tdata = FOOTER then

                                -- Packets with minutes and/or seconds outside valid ranges are entirely ignored
                                if temp_min <= 60 and temp_sec <= 59 then

                                    if reg_send_audio = '1' then -- Acquisition is running
                                        if temp_min = 0 and temp_sec = 0 then
                                            -- 00:00 packet stops the acquisition and clears the counters
                                            reg_send_audio <= '0';
                                            reg_min <= (others => '0');
                                            reg_sec <= (others => '0');
                                            tick_cnt <= 0;
                                        end if;
                                        -- All other packets are ignored while acquisition is running

                                    else -- Acquisition is stopped
                                        if not (temp_min = 0 and temp_sec = 0) then
                                            -- Start acquisition
                                            reg_send_audio <= '1';
                                            reg_min <= temp_min(5 downto 0);
                                            reg_sec <= temp_sec(5 downto 0);
                                            tick_cnt <= 0; -- Restart timer for exact 1-second ticks
                                        end if;
                                        -- 00:00 packets are naturally ignored while acquisition is stopped
                                    end if;

                                end if;
                            end if;

                            state <= WAIT_HEADER; -- Always return to header state after receiving footer, regardless of its validity

                    end case;
                end if;
            end if;
        end if;
    end process;
    -------------------------------

end architecture;
