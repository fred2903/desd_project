----------------------------------------------------------------------------------
-- Company: 
-- Engineer: 
-- 
-- Create Date: 23.07.2022 14:18:26
-- Design Name: 
-- Module Name: Reverb - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity reverb is
    generic(
        LOG2_DELAY_INCR : integer :=1;              -- CONSTANT DO NOT TOUCH
        CHANNEL_LENGHT  : integer := 24;            -- 3 byte for audio
        DELAY_LENGHT  : integer := 10;              -- JSTK axis dimension
        DELAY_INIT : integer := 882;                -- 20 ms                    INIT VALUE  DO NOT TOUCH
        GAIN_LENGHT : integer := 10;                -- JSTK axis dimension
        GAIN_INIT_FRAC : integer := 614;            --614/(2^10) ~= 0.6         INIT VALUE  DO NOT TOUCH
        HIGHER_BOUND	: integer := 2**23-1;	    -- Inclusive (max value of TDATA at 24 bit signed)
		LOWER_BOUND		: integer := -2**23		    -- Inclusive (min value of TDATA at 24 bit signed)
    );
    Port (
        
            aclk			: in std_logic;
            aresetn			: in std_logic;
            
            enable_reverb   : in std_logic;

            delay_in        : in std_logic_vector(DELAY_LENGHT-1 downto 0);

            gain_in         : in std_logic_vector(GAIN_LENGHT-1 downto 0);
    
            s_axis_tvalid	: in std_logic;
            s_axis_tdata	: in std_logic_vector(CHANNEL_LENGHT-1 downto 0);
            s_axis_tlast    : in std_logic;
            s_axis_tready	: out std_logic;
    
            m_axis_tvalid	: out std_logic;
            m_axis_tdata	: out std_logic_vector(CHANNEL_LENGHT-1 downto 0);
            m_axis_tlast	: out std_logic;
            m_axis_tready	: in std_logic
        );
end reverb;

architecture Behavioral of reverb is
    component delay is
        generic(
            CHANNEL_LENGHT  : integer;
            DELAY_LENGHT  : integer;
            DELAY_INIT : integer;
            LOG2_DELAY_INCR : integer
        );
        Port (
            
                aclk			: in std_logic;
                aresetn			: in std_logic;
                
                delay_in        : in std_logic_vector(DELAY_LENGHT-1 downto 0);
        
                data_in	        : in std_logic_vector(CHANNEL_LENGHT-1 downto 0);
                data_in_valid	: in std_logic;
        
                data_out	    : out std_logic_vector(CHANNEL_LENGHT-1 downto 0)
        );
    end component;

begin

end Behavioral;
