# === GAME CONFIGURATION ===

# === ENUMS ===
enum PlayerAction { Left; Right; SoftDrop; RotateCW; HardDrop; Pause; Quit }

# === GAMEPLAY DIMENSIONS ===
$script:BOARD_WIDTH     = 10
$script:BOARD_HEIGHT    = 22
$script:SPAWN_Y_OFFSET  = -2

# === GAME SPEED / TIMING ===
$script:LINES_PER_LEVEL     = 10
$script:GRAVITY_INTERVALS   = @(800,717,633,550,467,383,300,217,133,100,83,83,83,67,67,67,50,50,50,33,33,33,33,33,33,33,33,33,33,17)

# DAS (Delayed Auto-Shift)
$script:DAS_DELAY_MS    = 200
$script:DAS_INTERVAL_MS = 50

# Lock delay behavior
$script:LOCK_DELAY_MS    = 500
$script:LOCK_RESET_LIMIT = 2

# === TETROMINO CONFIGURATION ===
$script:TETROMINO_IDS = @('T', 'L', 'Z', 'O', 'S', 'J', 'I')

# === RENDERING CHARACTERS ===
$script:CHAR_SOLID = '▓'
$script:CHAR_GHOST = '░'
$script:CHAR_EMPTY = ' '

# === UI DIMENSIONS ===
$script:RENDER_CELL_WIDTH = 2

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
$script:LINE_CLEAR_SCORES = @(0, 40, 100, 300, 1200)

# === COLORS ===
$script:colors = @{
    I = @(255, 179, 71)
    O = @(255, 213, 102)
    T = @(218, 112, 214)
    S = @(255, 128, 0)
    Z = @(220, 20, 60)
    J = @(255, 99, 71)
    L = @(255, 140, 0)
}

$script:bgColors = @{
    I = @(100, 60, 30)
    O = @(110, 90, 30)
    T = @(90, 40, 70)
    S = @(130, 70, 20)
    Z = @(100, 30, 30)
    J = @(120, 50, 40)
    L = @(130, 80, 20)
}