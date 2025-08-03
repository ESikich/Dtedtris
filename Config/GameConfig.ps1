# === GAME CONFIGURATION ===

# === ENUMS ===
enum PlayerAction { Left; Right; SoftDrop; RotateCW; HardDrop; Pause; Quit }

# === GAMEPLAY DIMENSIONS ===
$script:BOARD_WIDTH     = 10
$script:BOARD_HEIGHT    = 22
$script:SPAWN_Y_OFFSET  = -2

# === GAME SPEED / TIMING ===
$script:LINES_PER_LEVEL     = 10
# NES-accurate gravity intervals (ms per row drop) for levels 0-29
$script:GRAVITY_INTERVALS   = @(800,717,633,550,467,383,300,217,133,100,83,83,83,67,67,67,50,50,50,33,33,33,33,33,33,33,33,33,33,17)

# DAS (Delayed Auto-Shift) - controls how held keys repeat
$script:DAS_DELAY_MS    = 200  # Initial delay before key starts repeating
$script:DAS_INTERVAL_MS = 50   # Time between repeats once started

# Lock delay - prevents accidental locks when piece lands
$script:LOCK_DELAY_MS    = 500  # Grace period before piece locks
$script:LOCK_RESET_LIMIT = 2    # How many times movement can reset the delay

# === TETROMINO CONFIGURATION ===
$script:TETROMINO_IDS = @('T', 'L', 'Z', 'O', 'S', 'J', 'I')

# === RENDERING CHARACTERS ===
$script:CHAR_SOLID = '▓'
$script:CHAR_GHOST = '░'
$script:CHAR_EMPTY = ' '

# === UI DIMENSIONS ===
$script:RENDER_CELL_WIDTH = 2  # How many console characters per game cell

# Stats panel layout
$script:STATS_PANEL_WIDTH  = 15
$script:STATS_PANEL_HEIGHT = 28

# Score panel
$script:SCORE_PANEL_WIDTH  = 16
$script:SCORE_PANEL_HEIGHT = 2

# Next piece preview panel
$script:NEXT_PANEL_WIDTH   = 10
$script:NEXT_PANEL_HEIGHT  = 5

# === SCORING ===
# Points awarded for line clears (index = number of lines cleared)
$script:LINE_CLEAR_SCORES = @(0, 40, 100, 300, 1200)

# === COLORS ===
$script:colors = @{
    I = @(255, 179, 71)   # Orange
    O = @(255, 213, 102)  # Yellow
    T = @(218, 112, 214)  # Orchid
    S = @(255, 128, 0)    # Dark Orange
    Z = @(220, 20, 60)    # Crimson
    J = @(255, 99, 71)    # Tomato
    L = @(255, 140, 0)    # Dark Orange
}

$script:bgColors = @{
    I = @(100, 60, 30)    # Darker orange
    O = @(110, 90, 30)    # Darker yellow
    T = @(90, 40, 70)     # Darker orchid
    S = @(130, 70, 20)    # Darker orange
    Z = @(100, 30, 30)    # Darker crimson
    J = @(120, 50, 40)    # Darker tomato
    L = @(130, 80, 20)    # Darker orange
}