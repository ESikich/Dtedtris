# === GAME CONFIGURATION ===

# === ENUMS ===
enum PlayerAction { Left; Right; SoftDrop; RotateCW; HardDrop; Pause; Quit }

# Configuration class to encapsulate all game settings
class GameConfig {
    # === GAMEPLAY DIMENSIONS ===
    [int] $BOARD_WIDTH = 10
    [int] $BOARD_HEIGHT = 22
    [int] $SPAWN_Y_OFFSET = -2

    # === TIMING CONFIGURATION ===
    [int] $LINES_PER_LEVEL = 10
    # NES-accurate gravity intervals (ms per row drop) for levels 0-29
    [int[]] $GRAVITY_INTERVALS = @(800,717,633,550,467,383,300,217,133,100,83,83,83,67,67,67,50,50,50,33,33,33,33,33,33,33,33,33,33,17)

    # DAS (Delayed Auto-Shift) - controls how held keys repeat
    [int] $DAS_DELAY_MS = 200     # Initial delay before key starts repeating
    [int] $DAS_INTERVAL_MS = 50   # Time between repeats once started

    # Lock delay - prevents accidental locks when piece lands
    [int] $LOCK_DELAY_MS = 500    # Grace period before piece locks
    [int] $LOCK_RESET_LIMIT = 2   # How many times movement can reset the delay

    # === PIECE CONFIGURATION ===
    [string[]] $TETROMINO_IDS = @('T', 'L', 'Z', 'O', 'S', 'J', 'I')

    # === RENDERING CONFIGURATION ===
    [string] $CHAR_SOLID = '▓'
    [string] $CHAR_GHOST = '░'
    [string] $CHAR_EMPTY = ' '
    [int] $RENDER_CELL_WIDTH = 2  # How many console characters per game cell

    # === UI PANEL DIMENSIONS ===
    [int] $STATS_PANEL_WIDTH = 15
    [int] $STATS_PANEL_HEIGHT = 28
    [int] $SCORE_PANEL_WIDTH = 16
    [int] $SCORE_PANEL_HEIGHT = 2
    [int] $NEXT_PANEL_WIDTH = 10
    [int] $NEXT_PANEL_HEIGHT = 5

    # === SCORING SYSTEM ===
    # Points awarded for line clears (index = number of lines cleared)
    [int[]] $LINE_CLEAR_SCORES = @(0, 40, 100, 300, 1200)

    # === COLOR SCHEMES ===
    [hashtable] $Colors = @{
        I = @(255, 179, 71)   # Orange
        O = @(255, 213, 102)  # Yellow
        T = @(218, 112, 214)  # Orchid
        S = @(255, 128, 0)    # Dark Orange
        Z = @(220, 20, 60)    # Crimson
        J = @(255, 99, 71)    # Tomato
        L = @(255, 140, 0)    # Dark Orange
    }

    [hashtable] $BackgroundColors = @{
        I = @(100, 60, 30)    # Darker orange
        O = @(110, 90, 30)    # Darker yellow
        T = @(90, 40, 70)     # Darker orchid
        S = @(130, 70, 20)    # Darker orange
        Z = @(100, 30, 30)    # Darker crimson
        J = @(120, 50, 40)    # Darker tomato
        L = @(130, 80, 20)    # Darker orange
    }

    # Computed properties - set during initialization
    [hashtable] $TetrominoDims
    [hashtable] $TetrominoMasks
    [hashtable] $TetrominoKicks

    GameConfig() {
        # These will be populated by the tetromino data loading
    }

    [void] SetTetrominoData([hashtable]$dims, [hashtable]$masks, [hashtable]$kicks) {
        $this.TetrominoDims = $dims
        $this.TetrominoMasks = $masks
        $this.TetrominoKicks = $kicks
    }
}

# Create global configuration instance
$Global:GameConfig = [GameConfig]::new()

# Backward compatibility - expose individual variables for existing code
$script:BOARD_WIDTH = $Global:GameConfig.BOARD_WIDTH
$script:BOARD_HEIGHT = $Global:GameConfig.BOARD_HEIGHT
$script:SPAWN_Y_OFFSET = $Global:GameConfig.SPAWN_Y_OFFSET
$script:LINES_PER_LEVEL = $Global:GameConfig.LINES_PER_LEVEL
$script:GRAVITY_INTERVALS = $Global:GameConfig.GRAVITY_INTERVALS
$script:DAS_DELAY_MS = $Global:GameConfig.DAS_DELAY_MS
$script:DAS_INTERVAL_MS = $Global:GameConfig.DAS_INTERVAL_MS
$script:LOCK_DELAY_MS = $Global:GameConfig.LOCK_DELAY_MS
$script:LOCK_RESET_LIMIT = $Global:GameConfig.LOCK_RESET_LIMIT
$script:TETROMINO_IDS = $Global:GameConfig.TETROMINO_IDS
$script:CHAR_SOLID = $Global:GameConfig.CHAR_SOLID
$script:CHAR_GHOST = $Global:GameConfig.CHAR_GHOST
$script:CHAR_EMPTY = $Global:GameConfig.CHAR_EMPTY
$script:RENDER_CELL_WIDTH = $Global:GameConfig.RENDER_CELL_WIDTH
$script:STATS_PANEL_WIDTH = $Global:GameConfig.STATS_PANEL_WIDTH
$script:STATS_PANEL_HEIGHT = $Global:GameConfig.STATS_PANEL_HEIGHT
$script:SCORE_PANEL_WIDTH = $Global:GameConfig.SCORE_PANEL_WIDTH
$script:SCORE_PANEL_HEIGHT = $Global:GameConfig.SCORE_PANEL_HEIGHT
$script:NEXT_PANEL_WIDTH = $Global:GameConfig.NEXT_PANEL_WIDTH
$script:NEXT_PANEL_HEIGHT = $Global:GameConfig.NEXT_PANEL_HEIGHT
$script:LINE_CLEAR_SCORES = $Global:GameConfig.LINE_CLEAR_SCORES
$script:colors = $Global:GameConfig.Colors
$script:bgColors = $Global:GameConfig.BackgroundColors