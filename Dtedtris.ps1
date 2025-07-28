# === SCRIPT SETTINGS ===
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# === CONSOLE SETUP ===
$WINDOW_TITLE = 'Dtedtris'
[Console]::Title = $WINDOW_TITLE
[Console]::Clear()
[Console]::CursorVisible = $false

# === ENUMS ===
enum PlayerAction { Left; Right; SoftDrop; RotateCW; HardDrop; Pause; Quit }

# === GAMEPLAY DIMENSIONS ===
$BOARD_WIDTH     = 10
$BOARD_HEIGHT    = 22
$SPAWN_Y_OFFSET  = -2

# === GAME SPEED / TIMING ===
$LINES_PER_LEVEL     = 10
$GRAVITY_INTERVALS   = @(800,717,633,550,467,383,300,217,133,100,83,83,83,67,67,67,50,50,50,33,33,33,33,33,33,33,33,33,33,17)

# DAS (Delayed Auto-Shift)
$DAS_DELAY_MS    = 200
$DAS_INTERVAL_MS = 50

# Lock delay behavior
$LOCK_DELAY_MS    = 500
$LOCK_RESET_LIMIT = 2

# === TETROMINO CONFIGURATION ===
$TETROMINO_IDS = @('T', 'L', 'Z', 'O', 'S', 'J', 'I')

# === RENDERING CHARACTERS ===
$CHAR_SOLID = '▓'
$CHAR_GHOST = '░'
$CHAR_EMPTY = ' '

# === UI DIMENSIONS ===
$RENDER_CELL_WIDTH = 2

# Stats panel layout
$STATS_PANEL_WIDTH  = 15
$STATS_PANEL_HEIGHT = 28

# Score panel
$SCORE_PANEL_WIDTH  = 16
$SCORE_PANEL_HEIGHT = 2

# Next piece preview panel
$NEXT_PANEL_WIDTH   = 10
$NEXT_PANEL_HEIGHT  = 5

# === SCORING ===
$LINE_CLEAR_SCORES = @(0, 40, 100, 300, 1200)

# === COLORS ===
$colors = @{
    I = @(255, 179, 71)
    O = @(255, 213, 102)
    T = @(218, 112, 214)
    S = @(255, 128, 0)
    Z = @(220, 20, 60)
    J = @(255, 99, 71)
    L = @(255, 140, 0)
}

$bgColors = @{
    I = @(100, 60, 30)
    O = @(110, 90, 30)
    T = @(90, 40, 70)
    S = @(130, 70, 20)
    Z = @(100, 30, 30)
    J = @(120, 50, 40)
    L = @(130, 80, 20)
}

# === CURSOR STATE TRACKING (for perf optimizations) ===
$global:LastCursorPosition = "-1:-1"

function Get-Idx($x, $y, $width) {
	return ($y * $width) + $x
}

function Safe-SetCursorPosition {
    param([int]$x, [int]$y)

    $posKey = "$($x):$($y)"

    if ($posKey -ne $global:LastCursorPosition) {
        [Console]::SetCursorPosition($x, $y)
        $global:LastCursorPosition = $posKey
    }
}

class Point {
    [int] $X
    [int] $Y

    Point([int]$x, [int]$y) {
        $this.X = $x
        $this.Y = $y
    }

    [Point] Add([Point]$other) {
        return [Point]::new($this.X + $other.X, $this.Y + $other.Y)
    }

    [string] ToKey() {
        return "$($this.X):$($this.Y)"
    }
}

function Get-MinMax {
    param([Point[]]$arr)
    if (-not $arr -or $arr.Count -eq 0) {
        return @{ MinX = 0; MaxX = 0; MinY = 0; MaxY = 0 }
    }

    $minX = $maxX = $arr[0].X
    $minY = $maxY = $arr[0].Y
    foreach ($p in $arr) {
        if ($p.X -lt $minX) { $minX = $p.X }
        if ($p.X -gt $maxX) { $maxX = $p.X }
        if ($p.Y -lt $minY) { $minY = $p.Y }
        if ($p.Y -gt $maxY) { $maxY = $p.Y }
    }
    return @{ MinX = $minX; MaxX = $maxX; MinY = $minY; MaxY = $maxY }
}

# === TETROMINO DATA ===
$TetrominoBits = @{
    I = @(0x0F00, 0x2222, 0x00F0, 0x4444)
    O = @(0x6600, 0x6600, 0x6600, 0x6600)
    T = @(0x4E00, 0x4640, 0x0E40, 0x4C40)
    S = @(0x6C00, 0x4620, 0x06C0, 0x8C40)
    Z = @(0xC600, 0x2640, 0x0C60, 0x4C80)
    J = @(0x00E8, 0x0446, 0x02E0, 0x0C44)
    L = @(0x00E2, 0x0644, 0x08E0, 0x044C)
}

function Convert-BitsToPoints([int]$bits) {
    $list = [System.Collections.Generic.List[Point]]::new()
    for ($i = 0; $i -lt 16; $i++) {
        if ($bits -band (1 -shl (15 - $i))) {
            $x = $i % 4
            $y = [math]::Floor($i / 4)
            $list.Add([Point]::new($x, $y))
        }
    }
    return $list.ToArray()
}

function Expand-Mask16ToArray([int]$mask16) {

    function ReverseNibble([int]$n) {
        # b3 b2 b1 b0  →  b0 b1 b2 b3
        return  (
            (( $n             -band 1) * 8) +   # bit0 -> bit3
            ((($n -shr 1)     -band 1) * 4) +   # bit1 -> bit2
            ((($n -shr 2)     -band 1) * 2) +   # bit2 -> bit1
            ((($n -shr 3)     -band 1) * 1)     # bit3 -> bit0
        )
    }

    return @(
        [int](ReverseNibble(($mask16 -shr 12) -band 0xF)),
        [int](ReverseNibble(($mask16 -shr  8) -band 0xF)),
        [int](ReverseNibble(($mask16 -shr  4) -band 0xF)),
        [int](ReverseNibble(($mask16 -shr  0) -band 0xF))
    )
}

$TetrominoMasks = @{}
foreach ($id in $TetrominoBits.Keys) {
    $bitRotations = $TetrominoBits[$id]
    $expanded = @()
    foreach ($bits in $bitRotations) {
        $expanded += ,(Expand-Mask16ToArray $bits)
    }
    $TetrominoMasks[$id] = $expanded
}

# Keeps the expression of the data clean
function P($x, $y) { return [Point]::new([int]$x, [int]$y) }

# Precomputed tetromino shapes, each rotation as Point[]
$TetrominoShapes = @{}
foreach ($id in $TetrominoBits.Keys) {
    $list = [System.Collections.Generic.List[Point[]]]::new()
    foreach ($b in $TetrominoBits[$id]) {
        $list.Add((Convert-BitsToPoints $b))
    }
    $TetrominoShapes[$id] = $list.ToArray()
}

# === PRECOMPUTED DIMENSIONS (rotation 0 only) ===
$TetrominoDims = @{}
foreach ($id in $TetrominoShapes.Keys) {
	$shape = $TetrominoShapes[$id][0]  # rotation 0
	$minX = $maxX = $shape[0].X
	$minY = $maxY = $shape[0].Y

	foreach ($p in $shape) {
    	if ($p.X -lt $minX) { $minX = $p.X }
    	if ($p.X -gt $maxX) { $maxX = $p.X }
    	if ($p.Y -lt $minY) { $minY = $p.Y }
    	if ($p.Y -gt $maxY) { $maxY = $p.Y }
	}

	$TetrominoDims[$id] = @{
    	MinX   = $minX
    	MaxX   = $maxX
    	Width  = $maxX - $minX + 1
    	MinY   = $minY
    	MaxY   = $maxY
    	Height = $maxY - $minY + 1
	}
}

$TetrominoKicks = @{
	Default = @{
    	"0_1" = @((P 0 0),(P -1 0),(P -1 1),(P 0 -2),(P -1 -2))
    	"1_0" = @((P 0 0),(P  1 0),(P  1 -1),(P 0  2),(P  1  2))
    	"1_2" = @((P 0 0),(P  1 0),(P  1 1),(P 0 -2),(P  1 -2))
    	"2_1" = @((P 0 0),(P -1 0),(P -1 -1),(P 0  2),(P -1  2))
    	"2_3" = @((P 0 0),(P  1 0),(P  1 1),(P 0 -2),(P  1 -2))
    	"3_2" = @((P 0 0),(P -1 0),(P -1 -1),(P 0  2),(P -1  2))
    	"3_0" = @((P 0 0),(P -1 0),(P -1 1),(P 0 -2),(P -1 -2))
    	"0_3" = @((P 0 0),(P  1 0),(P  1 1),(P 0 -2),(P  1 -2))
	}

	I = @{
    	"0_1" = @((P 0 0), (P -2 0), (P 1 0),  (P -2 -1), (P 1 2))
    	"1_0" = @((P 0 0), (P 2 0),  (P -1 0), (P 2 1),   (P -1 -2))
    	"1_2" = @((P 0 0), (P -1 0), (P 2 0),  (P -1 2),  (P 2 -1))
    	"2_1" = @((P 0 0), (P 1 0),  (P -2 0), (P 1 -2),  (P -2 1))
    	"2_3" = @((P 0 0), (P 2 0),  (P -1 0), (P 2 1),   (P -1 -2))
    	"3_2" = @((P 0 0), (P -2 0), (P 1 0),  (P -2 -1), (P 1 2))
    	"3_0" = @((P 0 0), (P 1 0),  (P -2 0), (P 1 -2),  (P -2 1))
    	"0_3" = @((P 0 0), (P -1 0), (P 2 0),  (P -1 2),  (P 2 -1))
	}
}

class Panel {
    [int] $X
    [int] $Y
    [int] $Width
    [int] $Height
    [string] $Title

    hidden [hashtable] $__LastDrawnState = @{}

    Panel([int]$x, [int]$y, [int]$w, [int]$h, [string]$title = "") {
        $this.X = $x
        $this.Y = $y
        $this.Width = $w
        $this.Height = $h
        $this.Title = $title
    }

    [void] DrawFrame() {
	    $frameKey = "$($this.X):$($this.Y):$($this.Width):$($this.Height):$($this.Title)"

	    if ($this.__LastDrawnState.ContainsKey("frameKey") -and $this.__LastDrawnState["frameKey"] -eq $frameKey) {
    	    return  # Already drawn with same dimensions + title
	    }

	    $this.__LastDrawnState["frameKey"] = $frameKey

	    $frameTop = "┌" + ("─" * $this.Width) + "┐"

	    if ($this.Title) {
    	    $titleString = " $($this.Title) "
    	    $mid = [math]::Floor(($this.Width - $titleString.Length) / 2)
    	    $frameTop = "┌" + ("─" * $mid) + $titleString + ("─" * ($this.Width - $mid - $titleString.Length)) + "┐"
	    }

	    Safe-SetCursorPosition $this.X $this.Y
	    [Console]::Write($frameTop)

	    for ($row = 0; $row -lt $this.Height; $row++) {
    	    Safe-SetCursorPosition $this.X ($this.Y + 1 + $row)
    	    [Console]::Write("│")
    	    Safe-SetCursorPosition ($this.X + $this.Width + 1) ($this.Y + 1 + $row)
    	    [Console]::Write("│")
	    }

	    Safe-SetCursorPosition $this.X ($this.Y + $this.Height + 1)
	    [Console]::Write("└" + ("─" * $this.Width) + "┘")
    }
}

class ScorePanel : Panel {
	[int] $Score
	[int] $Lines
	[int] $Level
	[hashtable] $LastDrawnValue = @{}
	hidden [System.Collections.Generic.Dictionary[int,string]] $_RowCache

	ScorePanel([int]$x, [int]$y, [int]$w, [int]$h) : base($x, $y, $w, $h, "SCORE") {
    	$this._RowCache = [System.Collections.Generic.Dictionary[int,string]]::new()
	}

	[void] Render() {
    	$current = @{ Score = $this.Score }
    	if (-not (Compare-Hashtable $this.LastDrawnValue $current)) {
        	$this.DrawFrame()

        	$label = "Score: $($this.Score)"
        	$pad   = ' ' * [Math]::Max(0, $this.Width - $label.Length)
        	$final = $label + $pad

        	$rowY = $this.Y + 1
        	$rowX = $this.X + 1

        	if (-not $this._RowCache.ContainsKey($rowY) -or $this._RowCache[$rowY] -ne $final) {
            	[Console]::SetCursorPosition($rowX, $rowY)
            	[Console]::Write($final)
            	$this._RowCache[$rowY] = $final
        	}

        	$this.LastDrawnValue = $current.Clone()
    	}
	}
}

class LinesPanel : Panel {
    [int] $Lines
    [int] $LastDrawnLines = -1

    LinesPanel([int]$x, [int]$y, [int]$w, [int]$h) : base($x, $y, $w, $h, "") { }

    [void] Render() {
	    if ($this.Lines -ne $this.LastDrawnLines) {
    	    $this.DrawFrame()

    	    $label = "LINES - " + $this.Lines.ToString("D3")
    	    $textX = $this.X + [int](($this.Width - $label.Length) / 2) + 1
    	    $textY = $this.Y + 1  # First line inside the frame

    	    # Clear the entire text line inside the frame
    	    Safe-SetCursorPosition ($this.X + 1) $textY
    	    Write-Host -NoNewline (' ' * $this.Width)

    	    # Write the label centered
    	    Safe-SetCursorPosition $textX $textY
    	    Write-Host -NoNewline $label

    	    $this.LastDrawnLines = $this.Lines
	    }
    }
}

class LevelPanel : Panel {
	[int] $Level
	[int] $LastDrawnLevel = -1
	hidden [System.Collections.Generic.Dictionary[int,string]] $_RowCache

	LevelPanel([int]$x, [int]$y, [int]$w, [int]$h) : base($x, $y, $w, $h, "") {
    	$this._RowCache = [System.Collections.Generic.Dictionary[int,string]]::new()
	}

	[void] Render() {
    	if ($this.Level -ne $this.LastDrawnLevel) {
        	$this.DrawFrame()

        	$label1 = "LEVEL"
        	$label2 = $this.Level.ToString("D2")

        	$textY1 = $this.Y + 1
        	$textY2 = $this.Y + 2

        	$textX1 = $this.X + [int](($this.Width - $label1.Length) / 2) + 1
        	$textX2 = $this.X + [int](($this.Width - $label2.Length) / 2) + 1

        	# First row
        	if (-not $this._RowCache.ContainsKey($textY1) -or $this._RowCache[$textY1] -ne $label1) {
            	[Console]::SetCursorPosition($textX1, $textY1)
            	[Console]::Write($label1)
            	$this._RowCache[$textY1] = $label1
        	}

        	# Second row
        	if (-not $this._RowCache.ContainsKey($textY2) -or $this._RowCache[$textY2] -ne $label2) {
            	[Console]::SetCursorPosition($textX2, $textY2)
            	[Console]::Write($label2)
            	$this._RowCache[$textY2] = $label2
        	}

        	$this.LastDrawnLevel = $this.Level
    	}
	}
}

class NextPanel : Panel {
	[string] $NextId
	[hashtable] $Colors
	[string] $LastDrawnId = ''
	hidden [System.Collections.Generic.Dictionary[int,string]] $_RowCache
	hidden [System.Text.StringBuilder] $_LineBuilder

	NextPanel([int]$x, [int]$y, [int]$w, [int]$h, [hashtable]$colors) : base($x, $y, $w, $h, "NEXDT") {
    	$this.Colors = $colors
    	$this._RowCache = [System.Collections.Generic.Dictionary[int,string]]::new()
    	$this._LineBuilder = [System.Text.StringBuilder]::new(128)
	}

	[void] Render() {
    	if ($this.NextId -ne $this.LastDrawnId) {
        	$this.DrawFrame()
        	$this.DrawNextPreview()
        	$this.LastDrawnId = $this.NextId
    	}
	}

	[void] DrawNextPreview() {
    	$blocks = $script:TetrominoShapes[$this.NextId][0]
    	$rgb	= $this.Colors[$this.NextId]

    	$mm = Get-MinMax $blocks
    	$minX = $mm.MinX
    	$maxX = $mm.MaxX
    	$minY = $mm.MinY
    	$maxY = $mm.MaxY

    	$pieceWidth  = $maxX - $minX + 1
    	$pieceHeight = $maxY - $minY + 1

    	$cellWidth = $script:RENDER_CELL_WIDTH
    	$panelCols = $this.Width / $cellWidth
    	$panelRows = $this.Height

    	$offsetX = [math]::Floor(($panelCols  - $pieceWidth) / 2)
    	$offsetY = [math]::Floor(($panelRows - $pieceHeight) / 2)

    	# Build a map of which (x,y) cells are occupied
    	$occupied = @{}
    	foreach ($b in $blocks) {
        	$x = $b.X - $minX + $offsetX
        	$y = $b.Y - $minY + $offsetY
        	if ($x -ge 0 -and $x -lt $panelCols -and $y -ge 0 -and $y -lt $panelRows) {
            	$occupied["{$x}:{$y}"] = $true
        	}
    	}

    	$esc = [char]27
    	$ansiBlock = "$esc[38;2;$($rgb[0]);$($rgb[1]);$($rgb[2])m██$esc[0m"
    	$blank = ' ' * $cellWidth

    	for ($row = 0; $row -lt $this.Height; $row++) {
        	$this._LineBuilder.Clear()

        	for ($col = 0; $col -lt $panelCols; $col++) {
            	$key = "{$col}:{$row}"
            	if ($occupied.ContainsKey($key)) {
                	$null = $this._LineBuilder.Append($ansiBlock)
            	} else {
                	$null = $this._LineBuilder.Append($blank)
            	}
        	}

        	$str = $this._LineBuilder.ToString()
        	$consoleY = $this.Y + 1 + $row
        	$consoleX = $this.X + 1

        	if (-not $this._RowCache.ContainsKey($consoleY) -or $this._RowCache[$consoleY] -ne $str) {
            	[Console]::SetCursorPosition($consoleX, $consoleY)
            	[Console]::Write($str)
            	$this._RowCache[$consoleY] = $str
        	}
    	}
	}
}

function Compare-Hashtable($a, $b) {
    if ($a.Count -ne $b.Count) { return $false }
    foreach ($key in $a.Keys) {
        if (-not $b.ContainsKey($key)) { return $false }
        if ($a[$key] -ne $b[$key]) { return $false }
    }
    return $true
}

class StatsPanel : Panel {
	[hashtable] $Counts
	[hashtable] $LastDrawnCounts = @{}
	hidden [System.Text.StringBuilder] $_LineBuilder
	hidden [System.Collections.Generic.Dictionary[int,string]] $_RowCache

	StatsPanel([int]$x, [int]$y, [int]$w, [int]$h) : base($x, $y, $w, $h, "SDTADTS") {
    	$this.Counts = @{}
    	$this._RowCache = [System.Collections.Generic.Dictionary[int,string]]::new()
	}

	[void] Render() {
    	if (-not (Compare-Hashtable $this.LastDrawnCounts $this.Counts)) {
        	$this.DrawFrame()

        	if (-not $this._LineBuilder) {
            	$this._LineBuilder = [System.Text.StringBuilder]::new(128)
        	}

        	$cellW = $script:RENDER_CELL_WIDTH
        	$row = 0
        	$esc = [char]27

        	$this._RowCache.Clear()

        	foreach ($id in $script:TETROMINO_IDS) {
            	$count = if ($this.Counts.ContainsKey($id)) { $this.Counts[$id] } else { 0 }
            	$blocks = $script:TetrominoShapes[$id][0]
            	$color = $script:colors[$id]
            	$rgb   = "$esc[38;2;$($color[0]);$($color[1]);$($color[2])m"
            	$reset = "$esc[0m"

            	$mm = Get-MinMax $blocks
            	$minX = $mm.MinX; $minY = $mm.MinY
            	$offsetX = -$minX + 1
            	$offsetY = -$minY + 2

            	$occupied = @{}
            	foreach ($b in $blocks) {
                	$x = $b.X + $offsetX
                	$y = $b.Y + $offsetY
                	$occupied["{$x}:{$y}"] = $true
            	}

            	for ($dy = 0; $dy -lt 4; $dy++) {
                	$this._LineBuilder.Clear()

                	for ($dx = 0; $dx -lt 4; $dx++) {
                    	$key = "{$dx}:{$dy}"
                    	if ($occupied.ContainsKey($key)) {
                        	$null = $this._LineBuilder.Append("$rgb▓▓$reset")
                    	} else {
                        	$null = $this._LineBuilder.Append("  ")
                    	}
                	}

                	$drawY = $this.Y + 1 + $row + $dy
                	if ($drawY -ge ($this.Y + $this.Height)) { continue }

                	$drawX = $this.X + 1
                	$rowStr = $this._LineBuilder.ToString()

                	if (-not $this._RowCache.ContainsKey($drawY) -or $this._RowCache[$drawY] -ne $rowStr) {
                    	[Console]::SetCursorPosition($drawX, $drawY)
                    	[Console]::Write($rowStr)
                    	$this._RowCache[$drawY] = $rowStr
                	}
            	}

            	# Draw piece count (right-aligned)
            	$countStr = $count.ToString("D3")
            	$labelX = $this.X + 12
            	$labelY = $this.Y + $row + 3

            	if (-not $this._RowCache.ContainsKey($labelY) -or $this._RowCache[$labelY] -ne $countStr) {
                	[Console]::SetCursorPosition($labelX, $labelY)
                	[Console]::Write($countStr)
                	$this._RowCache[$labelY] = $countStr
            	}

            	$row += 4
            	if (($this.Y + 1 + $row) -ge ($this.Y + $this.Height)) { break }
        	}

        	$this.LastDrawnCounts = $this.Counts.Clone()
    	}
	}
}

class UIManager {
    [System.Collections.ArrayList] $Panels

    UIManager() {
        $this.Panels = @()
    }

    [void] AddPanel([Panel]$panel) {
        $this.Panels.Add($panel)
    }

	[void] Render() {
		foreach ($panel in $this.Panels) {
			if (
				$panel -is [ScorePanel] -or
				$panel -is [NextPanel] -or
				$panel -is [StatsPanel] -or
				$panel -is [LinesPanel] -or
				$panel -is [LevelPanel]
			) {
				$panel.Render()
			} else {
				$panel.DrawFrame()
			}
		}
	}
}

function LayoutTopStack($startX, $startY, $gap, [Panel[]]$panels) {
    $y = $startY
    foreach ($p in $panels) {
        $p.X = $startX
        $p.Y = $y
        $y += $p.Height + 2 + $gap  # frame border, +gap for spacing
    }
}

function HardDrop($app) {
    # Use the same fast distance calc as ghost
    $ghost = Get-GhostPieceFrom $app.Game.Board $app.Game.Active $app.Game.Ids
    $app.Game.Active.Y = $ghost.Y
    $app.Engine.ForceLock()
    $app.NeedsDraw = $true
}

function Show-SplashScreen {
    [Console]::Clear()
    [Console]::CursorVisible = $false

    $title = 'DTEDTRIS'
    $prompt = 'Press [Enter] to start'
    $boxWidth = [Math]::Max($title.Length, $prompt.Length) + 8

    $centerX = [int](([Console]::WindowWidth - $boxWidth) / 2)
    $centerY = [int](([Console]::WindowHeight) / 2) - 2

    function CenterWrite($y, $text) {
        $x = [int](([Console]::WindowWidth - $text.Length) / 2)
        Safe-SetCursorPosition $x $y
        Write-Host -NoNewline $text
    }

    CenterWrite ($centerY - 2) ("╔" + ("═" * ($boxWidth - 2)) + "╗")
    CenterWrite ($centerY - 1) ("║" + (" " * ($boxWidth - 2)) + "║")
    CenterWrite $centerY       ("║" + (" " * [int](($boxWidth - $title.Length) / 2 - 1)) + $title + (" " * [int](($boxWidth - $title.Length + 1) / 2 - 1)) + "║")
    CenterWrite ($centerY + 1) ("║" + (" " * [int](($boxWidth - $prompt.Length) / 2 - 1)) + $prompt + (" " * [int](($boxWidth - $prompt.Length + 1) / 2 - 1)) + "║")
    CenterWrite ($centerY + 2) ("║" + (" " * ($boxWidth - 2)) + "║")
    CenterWrite ($centerY + 3) ("╚" + ("═" * ($boxWidth - 2)) + "╝")

    do {
        $key = [Console]::ReadKey($true)
    } while ($key.Key -ne 'Enter')
}

function Show-GameOverScreen {
    $msg1 = 'GAME OVER'
    $msg2 = 'Press [R] to Restart or [Q] to Quit'

    $msgX1 = [int](([Console]::WindowWidth - $msg1.Length) / 2)
    $msgX2 = [int](([Console]::WindowWidth - $msg2.Length) / 2)
    $msgY  = [int](([Console]::WindowHeight) / 2)

    Safe-SetCursorPosition $msgX1 $msgY
    Write-Host -NoNewline $msg1
    Safe-SetCursorPosition $msgX2 ($msgY + 1)
    Write-Host -NoNewline $msg2
}

function Clear-GameOverScreen {
    $msg1 = 'GAME OVER'
    $msg2 = 'Press [R] to Restart or [Q] to Quit'

    $msgX1 = [int](([Console]::WindowWidth - $msg1.Length) / 2)
    $msgX2 = [int](([Console]::WindowWidth - $msg2.Length) / 2)
    $msgY  = [int](([Console]::WindowHeight) / 2)

    Safe-SetCursorPosition $msgX1 $msgY
    Write-Host -NoNewline (' ' * $msg1.Length)

    Safe-SetCursorPosition $msgX2 ($msgY + 1)
    Write-Host -NoNewline (' ' * $msg2.Length)
}

class InputManager {
    [hashtable] $HeldKeys = @{}
    [int]       $DASDelay
    [int]       $DASInterval

    InputManager([int]$delay,[int]$interval) {
        $this.DASDelay    = $delay
        $this.DASInterval = $interval
    }

    [PlayerAction[]] GetActions() {
	    $actions = @()
	    $now = [Environment]::TickCount

	    # Process new key presses
	    while ([Console]::KeyAvailable) {
    	    $kinfo = [Console]::ReadKey($true)
    	    $k = $kinfo.Key

    	    if (-not $this.HeldKeys.ContainsKey($k)) {
        	    switch ($k) {
            	    'LeftArrow'  { $actions += [PlayerAction]::Left 	}
            	    'RightArrow' { $actions += [PlayerAction]::Right	}
            	    'DownArrow'  { $actions += [PlayerAction]::SoftDrop }
            	    'UpArrow'	{ $actions += [PlayerAction]::RotateCW }
            	    'Spacebar'   { $actions += [PlayerAction]::HardDrop }
            	    'P'      	{ $actions += [PlayerAction]::Pause	}
            	    'Escape' 	{ $actions += [PlayerAction]::Quit 	}
        	    }

        	    # Track for DAS repeat
        	    $this.HeldKeys[$k] = @{
            	    PressedAt = $now
            	    LastFired = $now
        	    }
    	    }
	    }

	    # Process DAS repeats
	    foreach ($k in @($this.HeldKeys.Keys)) {
    	    $info = $this.HeldKeys[$k]
    	    if (-not $info -or -not $info.ContainsKey('PressedAt')) {
        	    continue
    	    }

    	    $elapsed   = $now - $info.PressedAt
    	    $sinceLast = $now - $info.LastFired

    	    $fireable  = ($k -eq 'DownArrow' -and $sinceLast -ge $this.DASInterval) -or
                 	    ($k -ne 'DownArrow' -and $elapsed -ge $this.DASDelay -and
                                        	    $sinceLast -ge $this.DASInterval)

    	    if ($fireable) {
        	    switch ($k) {
            	    'LeftArrow'  { $actions += [PlayerAction]::Left 	}
            	    'RightArrow' { $actions += [PlayerAction]::Right	}
            	    'DownArrow'  { $actions += [PlayerAction]::SoftDrop }
        	    }
        	    $info.LastFired = $now
    	    }
	    }

	    # Clear state if no keys are held (debounced)
	    if (-not [Console]::KeyAvailable -and $this.HeldKeys.Count -gt 0) {
    	    $this.HeldKeys.Clear()
	    }
	    return $actions
    }
}

class Tetromino {
    [string]   $Id
    [int]      $Rotation = 0
    [int]      $X
    [int]      $Y
    [hashtable] $KickData

    Tetromino([string]$id, [int]$x, [int]$y,
              [hashtable]$kickData) {
        $this.Id        = $id
        $this.X         = $x
        $this.Y         = $y
        $this.KickData  = $kickData
    }

    [Point[]] GetBlocks() {
        $relBlocks = $script:TetrominoShapes[$this.Id][$this.Rotation % 4]
        $count     = $relBlocks.Count
        $result    = [Point[]]::new($count)

        for ($i = 0; $i -lt $count; $i++) {
            $rel = $relBlocks[$i]
            $result[$i] = [Point]::new($this.X + $rel.X, $this.Y + $rel.Y)
        }

        return $result
    }

    [void] Rotate([int]$delta) {
        if ($this.Id -in @('S', 'Z')) {
            $this.Rotation = ($this.Rotation + $delta) % 2
        } else {
            $this.Rotation = ($this.Rotation + $delta) % 4
        }
    }

    [void] Move([int]$dx, [int]$dy) {
        $this.X += $dx
        $this.Y += $dy
    }

    [Tetromino] CloneMoved([int]$dx, [int]$dy, [int]$dr) {
        $newRot = ($this.Rotation + $dr)
        if ($this.Id -in @('S', 'Z')) {
            $newRot %= 2
        } else {
            $newRot %= 4
        }

        $copy = [Tetromino]::new(
            $this.Id,
            $this.X + $dx,
            $this.Y + $dy,
            $this.KickData
        )
        $copy.Rotation = $newRot
        return $copy
    }
}

class BitBoard {
    [int] $Width = 10
    [int] $Height = 22
    [System.UInt16[]] $Rows
    [string[,]] $Ids

    BitBoard() {
        $this.Rows = @(0) * $this.Height
        $this.Ids = [string[,]]::new($this.Height, $this.Width)
    }

    [bool] IsInside([int]$x, [int]$y) {
        return $x -ge 0 -and $x -lt $this.Width -and $y -ge 0 -and $y -lt $this.Height
    }

	[bool] CanPlaceMask([int[]]$mask, [int]$x, [int]$y) {

		for ($i = 0; $i -lt 4; $i++) {

			$rowBits = $mask[$i]
			if ($rowBits -eq 0) { continue }           # empty strip row – skip

			$yy = $y + $i
			if ($yy -ge $this.Height) { return $false } # below floor

			# ---------- horizontal shift ----------
			if ($x -lt 0) {
				$shift = -$x

				# bits that would fall off the left edge?
				if (($rowBits -band ((1 -shl $shift) - 1)) -ne 0) { return $false }

				$shifted = $rowBits -shr $shift
			}
			else {
				$shifted = $rowBits -shl $x

				# any bit past column 9?
				if ($shifted -gt 0x3FF) { return $false }
			}

			# ---------- collision with settled blocks ----------
			if ($yy -ge 0) {
				if (($this.Rows[$yy] -band $shifted) -ne 0) { return $false }
			}
		}

		return $true
	}

	[void] PlaceMask([int[]]$mask, [int]$x, [int]$y, [string]$id) {

		for ($i = 0; $i -lt 4; $i++) {

			$yy = $y + $i
			if ($yy -lt 0 -or $yy -ge $this.Height) { continue }

			# ------- shift mask row into board columns -------
			if ($x -lt 0) {
				$shifted = $mask[$i] -shr (-$x)      # flush-left cases
			} else {
				$shifted = $mask[$i] -shl  $x        # normal / right side
			}

			if ($shifted -eq 0) { continue }         # nothing to place this row

			# ------- stamp bits into playfield -------
			$this.Rows[$yy] = $this.Rows[$yy] -bor $shifted

			# ------- write colour / id map -------
			for ($bit = 0; $bit -lt $this.Width; $bit++) {
				if ($shifted -band (1 -shl $bit)) {
					$this.Ids[$yy, $bit] = $id
				}
			}
		}
	}

    [int] ClearLines() {
        $newRows = @(0) * $this.Height
        $newIds = [string[,]]::new($this.Height, $this.Width)
        $w = $this.Height - 1
        $cleared = 0
        for ($r = $this.Height - 1; $r -ge 0; $r--) {
            if ($this.Rows[$r] -eq 0x3FF) {
                $cleared++
                continue
            }
            $newRows[$w] = $this.Rows[$r]
            for ($c = 0; $c -lt $this.Width; $c++) {
                $newIds[$w, $c] = $this.Ids[$r, $c]
            }
            $w--
        }
        $this.Rows = $newRows
        $this.Ids = $newIds
        return $cleared
    }

	[int[]] GetFullLines() {
		$lines = @()
		for ($r = 0; $r -lt $this.Height; $r++) {
			if ($this.Rows[$r] -eq 0x3FF) {
				$lines += $r
			}
		}
		return $lines
	}
}

function Get-GhostPieceFrom([BitBoard]$board, [Tetromino]$active, [string[]]$ids) {

    # clone once; we’ll just adjust Y
    $ghost = $active.CloneMoved(0,0,0)

    # pre‑fetch the 4‑row piece mask we’ll use many times
    $mask = $script:TetrominoMasks[$ghost.Id][$ghost.Rotation % 4]

    # ----------------------------------------------------
    #   Compute “drop distance” with bit tricks
    # ----------------------------------------------------
    $drop = $board.Height    # start with a very large distance

    for ($i = 0; $i -lt 4; $i++) {

        $rowBits = $mask[$i]
        if ($rowBits -eq 0) { continue }         # empty stripe row

        $yy = $ghost.Y + $i
        if ($ghost.X -lt 0) {
            $shifted = $rowBits -shr -$ghost.X
        } else {
            $shifted = $rowBits -shl $ghost.X
        }

        # Scan downward until collision using bit masks only
        $d = 0
		while ($yy + $d + 1 -lt $board.Height) {
			$checkY = $yy + $d + 1
			if ($checkY -ge 0) {
				if (($board.Rows[$checkY] -band $shifted) -ne 0) { break }
			}
			$d++
		}
        if ($d -lt $drop) { $drop = $d }
    }

    $ghost.Y += $drop
    return $ghost
}

class GameContext {
    [int] $Width
    [int] $Height
    [BitBoard] $Board
    [Tetromino] $Active
    [string[]] $NextQueue
    [int] $Score
    [int] $Lines
    [int] $Level
    [bool] $Paused
    [bool] $GameOver
    [string[]] $Ids
    [int[]] $GravityIntervals
    [hashtable] $PieceCounts

    GameContext([int]$width, [int]$height, [string[]]$ids, [int[]]$gInt) {
        $this.Width = $width
        $this.Height = $height
        $this.Ids = $ids
        $this.GravityIntervals = $gInt

        $this.Board = [BitBoard]::new()
        $this.Active = $null
        $this.NextQueue = @()
        $this.Score = 0
        $this.Lines = 0
        $this.Level = 0
        $this.Paused = $false
        $this.GameOver = $false

        # Initialize piece count stats
        $this.PieceCounts = @{}
        foreach ($id in $ids) {
            $this.PieceCounts[$id] = 0
        }
    }
}
    
class GameEngine {
    [GameContext]   $Ctx
    [string[]]      $Bag = @()
    [int]           $GravityAccumulator = 0
    [int]           $MsPerGravity       = $script:GRAVITY_INTERVALS[0]
    [int]           $LockDelay          = $script:LOCK_DELAY_MS
    [Nullable[int]] $LockStartedAt      = $null
    [bool]          $LockDelayActive    = $false
    [int]           $LockResets         = 0
    [int]           $LockResetLimit     = $script:LOCK_RESET_LIMIT
	[int]           $LFSR
	[int]           $PrevIndex          = -1

    # ghost cache
    [Tetromino]     $GhostCache = $null
    [string]        $GhostKey   = ''

    GameEngine([GameContext]$ctx) {
        $this.Ctx = $ctx
		$this.LFSR = Get-Random -Minimum 1 -Maximum 128  # Initial seed (non-zero)
	}

	[bool] CanPlace([Tetromino]$p) {
		$id = $p.Id
		$rot = $p.Rotation % 4
		$mask = $script:TetrominoMasks[$id][$rot]
		return $this.Ctx.Board.CanPlaceMask($mask, $p.X, $p.Y)
	}

    [bool] IsGrounded() {
        if (-not $this.Ctx.Active) { return $false }
        return -not $this.CanPlace($this.Ctx.Active.CloneMoved(0, 1, 0))
    }

	[string] GetNextTetrominoId() {
		# Step 1: Advance LFSR (7-bit)
		$bit0 = $this.LFSR -band 1
		$bit1 = ($this.LFSR -shr 1) -band 1
		$newBit = $bit0 -bxor $bit1
		$this.LFSR = ($this.LFSR -shr 1) -bor ($newBit -shl 6)

		if ($this.LFSR -eq 0) {
			$this.LFSR = 0x1F  # reset if stuck (never zero in real LFSR)
		}

		# Step 2: Get a candidate index
		$index = $this.LFSR % 7

		# NES retry rule: If same as previous, pick again (once)
		if ($index -eq $this.PrevIndex) {
			$this.LFSR = ($this.LFSR -shr 1) -bor (($this.LFSR -bxor ($this.LFSR -shr 1)) -shl 6)
			if ($this.LFSR -eq 0) {
				$this.LFSR = 0x1F
			}
			$index = $this.LFSR % 7
		}

		$this.PrevIndex = $index
		return $this.Ctx.Ids[$index]
	}

	[GameState] TakeSnapshot() {
		$next = ''
		if ($this.Ctx.NextQueue.Count -gt 0) {
			$next = $this.Ctx.NextQueue[0]
		}

		$ghost = $this.GetGhostCached()

		return [GameState]::new(
			$this.Ctx.Board,
			$this.Ctx.Active,
			$ghost,
			$next,
			$this.Ctx.Score,
			$this.Ctx.Lines,
			$this.Ctx.Level,
			$this.Ctx.Paused,
			$this.Ctx.GameOver,
			$this.Ctx.PieceCounts
		)
	}

    [GameState] Update([int]$dt) {
	    if ($this.Ctx.GameOver) { return $null }

	    $changed = $false
	    $this.GravityAccumulator += $dt
	    $this.MsPerGravity = $this.Ctx.GravityIntervals[
    	    [math]::Min($this.Ctx.Level, $this.Ctx.GravityIntervals.Count - 1)
	    ]

	    if ($this.GravityAccumulator -ge $this.MsPerGravity) {
    	    $this.GravityAccumulator -= $this.MsPerGravity

    	    if ($this.TryMove(0, 1, 0)) {
        	    $this.LockDelayActive = $false
        	    $this.LockResets  	= 0
        	    $this.LockStartedAt   = $null
        	    $changed = $true
    	    } else {
        	    $now = [Environment]::TickCount

        	    if (-not $this.LockDelayActive) {
            	    $this.LockDelayActive = $true
            	    $this.LockStartedAt   = $now
            	    $changed = $true
        	    } elseif (($this.LockStartedAt -ne $null) -and ($now - $this.LockStartedAt) -ge $this.LockDelay) {
            	    $this.ForceLock()
            	    $changed = $true
        	    }
    	    }
	    }

	    if ($changed) {
    	    return $this.TakeSnapshot()
	    }

	    return $null
    }

    [bool] TryMove([int]$dx, [int]$dy, [int]$dr) {
	    $next = $this.Ctx.Active.CloneMoved($dx, $dy, $dr)
	    if (-not $this.CanPlace($next)) { return $false }

	    $this.Ctx.Active = $next

	    if ($this.LockDelayActive -and $this.IsGrounded() -and
    	    $this.LockResets -lt $this.LockResetLimit) {

    	    # Cache time
    	    $this.LockStartedAt = [Environment]::TickCount
    	    $this.LockResets++
	    }

	    return $true
    }

    [bool] TryRotateWithWallKick([Tetromino]$piece, [int]$dir) {
	    $old = $piece.Rotation % 4
	    $new = ($old + $dir) % 4
	    $key = "${old}_${new}"

	    $table = if ($piece.Id -eq 'I') {
    	    $script:TetrominoKicks.I[$key]
	    } else {
    	    $script:TetrominoKicks.Default[$key]
	    }

	    foreach ($kick in $table) {
    	    $test = $piece.CloneMoved($kick.X, $kick.Y, $dir)
    	    if ($this.CanPlace($test)) {
        	    $this.Ctx.Active = $test

        	    if ($this.LockDelayActive -and $this.IsGrounded() -and
            	    $this.LockResets -lt $this.LockResetLimit) {

            	    $this.LockStartedAt = [Environment]::TickCount
            	    $this.LockResets++
        	    }

        	    return $true
    	    }
	    }

	    return $false
    }

    [void] Spawn() {
	    if (-not $this.Ctx.NextQueue) {
    	    $this.Ctx.NextQueue = @($this.GetNextTetrominoId())
	    }

	    $id = $this.Ctx.NextQueue[0]
	    $this.Ctx.NextQueue = ,($this.GetNextTetrominoId())

	    # Increment piece count
	    if (-not $this.Ctx.PieceCounts.ContainsKey($id)) {
    	    $this.Ctx.PieceCounts[$id] = 0
	    }
	    $this.Ctx.PieceCounts[$id]++

        # --- X centering (precomputed) ---
        $dim = $script:TetrominoDims[$id]
        $x   = [math]::Floor(($this.Ctx.Width - $dim.Width) / 2) - $dim.MinX

	    $this.Ctx.Active = [Tetromino]::new(
    	    $id,
    	    $x,
    	    $script:SPAWN_Y_OFFSET,
    	    $script:TetrominoKicks
	    )

	    if (-not $this.CanPlace($this.Ctx.Active)) {
    	    $this.Ctx.GameOver = $true
	    } elseif ($this.TryMove(0, 1, 0)) {
    	    $null = $this.TryMove(0, -1, 0)
	    } else {
    	    $this.Ctx.GameOver = $true
	    }
    }

	[void] ForceLock() {
		if (-not $this.Ctx.Active) { return }

		$id = $this.Ctx.Active.Id
		$rot = $this.Ctx.Active.Rotation % 4
		$mask = $script:TetrominoMasks[$id][$rot]

		$this.Ctx.Board.PlaceMask($mask, $this.Ctx.Active.X, $this.Ctx.Active.Y, $id)

		# Step 1: Detect full lines
		$fullLines = $this.Ctx.Board.GetFullLines()

		# Step 2: Flash them if any
		if ($fullLines.Count -gt 0 -and $global:app -and $global:app.Renderer) {
			$global:app.Renderer.FlashLines($fullLines, 4, 32)  # X flickers, Y ms
		}

		# Step 3: Clear them and apply scoring
		$cleared = $this.Ctx.Board.ClearLines()
		if ($cleared -gt 0) {
			$this.Ctx.Lines += $cleared
			$this.Ctx.Level = [math]::Floor($this.Ctx.Lines / $script:LINES_PER_LEVEL)
			$this.Ctx.Score += $script:LINE_CLEAR_SCORES[$cleared] * ($this.Ctx.Level + 1)
		}

		$this.Spawn()
		$this.LockDelayActive = $false
		$this.LockStartedAt   = $null
		$this.LockResets      = 0
	}

    [string] MakeGhostKey([Tetromino]$piece) {
        return "{0}:{1}:{2}:{3}" -f $piece.Id, $piece.X, $piece.Y, ($piece.Rotation % 4)
    }

    [Tetromino] GetGhostCached() {
        $active = $this.Ctx.Active
        #if (-not $active) { return $null }

        $newKey = $this.MakeGhostKey($active)

        if ($this.GhostKey -ne $newKey) {
            $this.GhostCache = Get-GhostPieceFrom $this.Ctx.Board $active $this.Ctx.Ids
            $this.GhostKey   = $newKey
        }

        return $this.GhostCache
    }
}

class GameState {
    [System.UInt16[]] $Rows
	[string[,]]   $Ids
    [Tetromino]  $ActivePiece
    [Tetromino]  $GhostPiece
    [string]     $NextPieceId
    [int]        $Score
    [int]        $Lines
    [int]        $Level
    [bool]       $Paused
    [bool]       $GameOver
    [hashtable]  $PieceStats

	GameState(
		[BitBoard]      $board,
		[Tetromino]  $active,
		[Tetromino]  $ghost,
		[string]     $next,
		[int]        $score,
		[int]        $lines,
		[int]        $lvl,
		[bool]       $paused,
		[bool]       $go,
		[hashtable]  $pieceStats
	) {
		$this.Rows        = $board.Rows.Clone()
		$this.Ids         = $board.Ids.Clone()
		$this.ActivePiece = $active
		$this.GhostPiece  = $ghost
		$this.NextPieceId = $next
		$this.Score       = $score
		$this.Lines       = $lines
		$this.Level       = $lvl
		$this.Paused      = $paused
		$this.GameOver    = $go
		$this.PieceStats  = $pieceStats.Clone()
	}
}

class ConsoleRenderer {
	[int]       	$Width
	[int]       	$Height
	[hashtable] 	$Colors
	[hashtable] 	$AnsiCache
	[System.Collections.Generic.Dictionary[int,string]] $LastDrawn
	[string]    	$LastNextPieceId = ""
	[int]       	$LeftPanelWidth = 0
	[int]       	$Gap        	= 30
	[int]       	$HorizontalSpacer = 1
	[UIManager] 	$UI
	[hashtable] 	$BoardFrame = @{}
	[hashtable] 	$LastGhostKeys = @{}
	[hashtable] 	$PreviousGhostBlocks = @{}
    hidden [bool] $_PlayfieldFrameDrawn = $false
	hidden [System.Text.StringBuilder] $_LineBuilder
	hidden [System.Text.StringBuilder] $_FrameBuilder
    hidden [string[]] $_LastGhostKeys = @()
    hidden [string[,]] $_LastDrawnCells
	hidden [System.Collections.Generic.Dictionary[int,string]] $_RowCache = @{}

	ConsoleRenderer([int]$width, [int]$height, [hashtable]$colors) {
    	$this.Width = $width
    	$this.Height = $height
        $this._LastDrawnCells = [string[,]]::new($this.Height, $this.Width)
    	$this.Colors = $colors
    	$this.UI = [UIManager]::new()
    	$this.LastDrawn = [System.Collections.Generic.Dictionary[int,string]]::new()
        $this.BoardFrame = @{ X = 0; Y = 0; W = 0; H = 0 }
		$this._LineBuilder = [System.Text.StringBuilder]::new(256)
		$this._RowCache    = [System.Collections.Generic.Dictionary[int,string]]::new()

    	# Precompute ANSI cache once
    	$this.AnsiCache = @{}
    	$esc = [char]27

    	foreach ($id in $colors.Keys) {
        	$rgb = $colors[$id]
        	$bg  = $script:bgColors[$id]  # assuming bgColors is global

        	$fg  = "$esc[38;2;$($rgb[0]);$($rgb[1]);$($rgb[2])m"
        	$bgc = "$esc[48;2;$($bg[0]);$($bg[1]);$($bg[2])m"

        	$solid = "$fg$bgc$($script:CHAR_SOLID * $script:RENDER_CELL_WIDTH)$esc[0m"
        	$ghost = "$fg$($script:CHAR_GHOST * $script:RENDER_CELL_WIDTH)$esc[0m"

        	$this.AnsiCache[$id] = @{ solid = $solid; ghost = $ghost }
    	}
	}

	[void] DrawBoard(
		[GameState]   $state,
		[string[]]    $ids,
		[hashtable]   $colors,
		[hashtable]   $bgColors,
		[int]         $interiorX,
		[int]         $interiorY
	) {
		$rows   = $state.Rows
		$idsMap = $state.Ids
		$active = $state.ActivePiece
		$ghost  = $state.GhostPiece

		$cellWidth  = $script:RENDER_CELL_WIDTH
		$fieldWChar = $this.Width * $cellWidth
		$fieldHRows = $this.Height

		if (-not $this._PlayfieldFrameDrawn) {
			$this.DrawFrame($interiorX, $interiorY, $fieldWChar, $fieldHRows, "")
			$this._PlayfieldFrameDrawn = $true
		}

		$inX = $interiorX + 1
		$inY = $interiorY + 1

		$activeBlocks = @{}
		$ghostBlocks  = @{}
		$currentGhostKeys = @()

		if ($active) {
			foreach ($b in $active.GetBlocks()) {
				$idx = $b.X + ($b.Y * $this.Width)
				$activeBlocks[$idx] = $active.Id
			}
		}

		if ($ghost) {
			foreach ($b in $ghost.GetBlocks()) {
				$idx = $b.X + ($b.Y * $this.Width)
				$ghostBlocks[$idx] = $ghost.Id
				$currentGhostKeys += "$($b.X):$($b.Y)"
			}
		}

		for ($y = 0; $y -lt $fieldHRows; $y++) {

			# Build the full line once in a StringBuilder
			$this._LineBuilder.Clear()

			for ($x = 0; $x -lt $this.Width; $x++) {

				$idx = $x + ($y * $this.Width)
				$char = $script:CHAR_EMPTY
				$id = $null

				$cellSet = ($rows[$y] -band (1 -shl $x)) -ne 0

				if ($activeBlocks.ContainsKey($idx)) {
					$char = $script:CHAR_SOLID
					$id = $activeBlocks[$idx]
				} elseif ($cellSet) {
					$char = $script:CHAR_SOLID
					$id = $idsMap[$y, $x]
				} elseif ($ghostBlocks.ContainsKey($idx)) {
					$char = $script:CHAR_GHOST
					$id = $ghostBlocks[$idx]
				}

				if (-not $id -or -not $this.AnsiCache.ContainsKey($id)) {
					$id = 'Fallback'
				}

				switch ($char) {
					$script:CHAR_GHOST { $null = $this._LineBuilder.Append($this.AnsiCache[$id]['ghost']) }
					$script:CHAR_SOLID { $null = $this._LineBuilder.Append($this.AnsiCache[$id]['solid']) }
					default            { $null = $this._LineBuilder.Append(' ' * $cellWidth) }
				}
			}

			$fullLine = $this._LineBuilder.ToString()
			if ($this._RowCache[$y] -ne $fullLine) {
				[Console]::SetCursorPosition($inX, $inY + $y)
				[Console]::Write($fullLine)
				$this._RowCache[$y] = $fullLine
			}
		}
	}

    [void] SetupUIPanels([GameState] $state, [hashtable] $colors) {
	    $this.Gap = 1  # one-column gutter everywhere

	    # 1. Stats panel (left)
	    $statsX 	= $this.Gap
	    $statsPanel = [StatsPanel]::new(
    	    $statsX,
    	    0,
    	    $script:STATS_PANEL_WIDTH,
    	    $script:STATS_PANEL_HEIGHT
	    )
	    $this.UI.AddPanel($statsPanel)

	    # 2. Game board (center)
	    $boardX = $statsX + $script:STATS_PANEL_WIDTH + 2 + $this.Gap
	    $boardY = 3  # leave space above for Lines panel
	    $boardW = $script:BOARD_WIDTH  * $script:RENDER_CELL_WIDTH
	    $boardH = $script:BOARD_HEIGHT + 2  # with frame

	    # Lines label panel above the game board
	    $linesPanel = [LinesPanel]::new($boardX, 0, $boardW, 1)
	    $this.UI.AddPanel($linesPanel)

	    # Store where the board is located for DrawBoard()
	    $this.BoardFrame = @{
    	    X = $boardX
    	    Y = $boardY
    	    W = $boardW
    	    H = $boardH
	    }

	    # 3. HUD column (right side)
	    $hudX = $boardX + $boardW + 2 + $this.Gap

	    $scorePanel = [ScorePanel]::new(
    	    0,
    	    0,
    	    $script:SCORE_PANEL_WIDTH,
    	    $script:SCORE_PANEL_HEIGHT
	    )

	    $nextPanel = [NextPanel]::new(
    	    0,
    	    0,
    	    $script:NEXT_PANEL_WIDTH,
    	    $script:NEXT_PANEL_HEIGHT,
    	    $colors
	    )

	    $levelPanel = [LevelPanel]::new(
    	    0,
    	    0,
    	    $script:NEXT_PANEL_WIDTH,
    	    2
	    )

	    # Stack the HUD panels vertically on the right
	    LayoutTopStack $hudX 0 0 @($scorePanel, $nextPanel, $levelPanel)

	    $this.UI.AddPanel($scorePanel)
	    $this.UI.AddPanel($nextPanel)
	    $this.UI.AddPanel($levelPanel)
    }

    [void] Draw([GameState] $state, [hashtable] $colors, [hashtable] $bgColors, [string[]] $ids) {
	    # Ensure UI and board layout are set up before drawing
	    if (
    	    $this.UI.Panels.Count -eq 0 -or
    	    -not $this.BoardFrame.ContainsKey("X") -or
    	    -not $this.BoardFrame.ContainsKey("Y")
	    ) {
    	    $this.SetupUIPanels($state, $colors)
	    }

	    # Update panel contents with latest game state
	    foreach ($panel in $this.UI.Panels) {
    	    if ($panel -is [ScorePanel]) {
        	    $panel.Score = $state.Score
        	    $panel.Lines = $state.Lines
        	    $panel.Level = $state.Level
    	    } elseif ($panel -is [LevelPanel]) {
        	    $panel.Level = $state.Level
    	    } elseif ($panel -is [NextPanel]) {
        	    $panel.NextId = $state.NextPieceId
    	    } elseif ($panel -is [StatsPanel]) {
        	    $panel.Counts = $state.PieceStats
    	    } elseif ($panel -is [LinesPanel]) {
        	    $panel.Lines = $state.Lines
    	    }
	    }

	    # Draw the playfield
	    $this.DrawBoard(
    	    $state,
    	    $ids,
    	    $colors,
    	    $bgColors,
    	    $this.BoardFrame.X,
    	    $this.BoardFrame.Y
	    )

	    # Render HUD/UI
	    $this.UI.Render()
    }

	[void] FlashLines([int[]] $lineIndices, [int] $flickerCount = 4, [int] $frameDelayMs = 80) {
		$esc = [char]27
		$cellW = $script:RENDER_CELL_WIDTH
		$inX = $this.BoardFrame.X + 1
		$inY = $this.BoardFrame.Y + 1

		for ($i = 0; $i -lt $flickerCount; $i++) {
			foreach ($y in $lineIndices) {
				$str = ''
				for ($x = 0; $x -lt $this.Width; $x++) {
					if ($i % 2 -eq 0) {
						$str += "$esc[7m" + (' ' * $cellW) + "$esc[0m"  # Inverted
					} else {
						$str += (' ' * $cellW)                          # Clear
					}
				}
				[Console]::SetCursorPosition($inX, $inY + $y)
				[Console]::Write($str)
			}
			Start-Sleep -Milliseconds $frameDelayMs
		}
	}

	[void] DrawSpacer([int]$x) {
    	for ($y = 0; $y -lt $this.Height; $y++) {
        	Safe-SetCursorPosition ($x + 1) (1 + $y)
        	Write-Host -NoNewline " "
    	}
	}

    [void] DrawFrame([int]$x, [int]$y, [int]$wChars, [int]$hRows, [string]$title = "") {
	    $panel = [Panel]::new($x, $y, $wChars, $hRows, $title)
	    $panel.DrawFrame()
    }
}

class GameApp {
    [GameContext]     $Game
    [GameEngine]      $Engine
    [ConsoleRenderer] $Renderer
    [bool]            $NeedsDraw = $true

    [hashtable] $Colors
    [hashtable] $BackgroundColors

    GameApp([int]$w,[int]$h,[string[]]$ids,[int[]]$gInt,
            [hashtable]$colors,[hashtable]$bgColors) {

        $this.Game      = [GameContext]::new($w,$h,$ids,$gInt)
        $this.Engine    = [GameEngine]::new($this.Game)
        $this.Renderer  = [ConsoleRenderer]::new($w,$h,$colors)
        $this.Colors    = $colors
        $this.BackgroundColors = $bgColors
    }
}

# === MAIN LOOP ===
$sw = [System.Diagnostics.Stopwatch]::StartNew()
Show-SplashScreen
cls
do {
	$restart = $false

    $app   = [GameApp]::new($BOARD_WIDTH, $BOARD_HEIGHT, $TETROMINO_IDS, $GRAVITY_INTERVALS, $colors, $bgColors)
    $app.Renderer._PlayfieldFrameDrawn = $false
	$input = [InputManager]::new($DAS_DELAY_MS, $DAS_INTERVAL_MS)
	$app.Engine.Spawn()

    $sw.Restart()

	while (-not $app.Game.GameOver) {
    	$dt = $sw.ElapsedMilliseconds
    	$sw.Restart()

    	if (-not $app.Game.Paused) {
        	# === Handle input ===
        	foreach ($act in $input.GetActions()) {
            	switch ($act) {
                	'Left'  	{ if ($app.Engine.TryMove(-1,0,0)) { $app.NeedsDraw = $true } }
                	'Right' 	{ if ($app.Engine.TryMove( 1,0,0)) { $app.NeedsDraw = $true } }
                	'SoftDrop' {
                    	if ($app.Engine.TryMove(0, 1, 0)) {
                        	$app.NeedsDraw = $true
                    	} elseif ($app.Engine.IsGrounded()) {
                        	$app.Engine.ForceLock()
                        	$app.NeedsDraw = $true
                    	}
                	}
                	'RotateCW'  { if ($app.Engine.TryRotateWithWallKick($app.Game.Active,1)) { $app.NeedsDraw = $true } }
                	'HardDrop'  { HardDrop $app }
                	'Pause' 	{ $app.Game.Paused = $true; $app.NeedsDraw = $true }
                	'Quit'  	{ $app.Game.GameOver = $true }
            	}
        	}

        	# === Apply gravity, etc. ===
        	$state = $app.Engine.Update($dt)
        	if ($state) { $app.NeedsDraw = $true }

        	# === Redraw if needed ===
        	if ($app.NeedsDraw) {
            	if (-not $state) { $state = $app.Engine.TakeSnapshot() }
            	$app.Renderer.Draw($state, $app.Colors, $app.BackgroundColors, $app.Game.Ids)
            	$app.NeedsDraw = $false
        	}
    	} else {
        	# === Pause mode ===
        	$msg = '[ PAUSED ]'
        	$msgLength = $msg.Length
        	$centerX = [int](([Console]::WindowWidth  - $msgLength) / 2)
        	$centerY = [int](([Console]::WindowHeight) / 2)

        	Safe-SetCursorPosition $centerX $centerY
        	Write-Host -NoNewline $msg

        	do {
            	$key = [Console]::ReadKey($true)
            	if ($key.Key -eq 'P') {
                	Safe-SetCursorPosition $centerX $centerY
                	Write-Host -NoNewline (' ' * $msgLength)
                	$app.Game.Paused = $false
                	$app.NeedsDraw = $true
                	$sw.Restart()
                	break
            	}
        	} while ($true)
    	}

    	# === Idle sleep if nothing to do ===
    	if (-not [Console]::KeyAvailable -and -not $app.NeedsDraw) {
        	Start-Sleep -Milliseconds 1
    	}
	}

	Show-GameOverScreen

	do {
    	$key = [Console]::ReadKey($true)
    	$ch = [char]::ToUpper($key.KeyChar)
    	if ($ch -eq 'R') {
        	$restart = $true
        	break
    	} elseif ($ch -eq 'Q' -or $ch -eq 'C') {
        	$restart = $false
        	break
    	}
	} while ($true)

	Clear-GameOverScreen

} while ($restart)
