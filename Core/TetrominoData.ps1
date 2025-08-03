# === TETROMINO DATA ===

# Raw bit patterns for each tetromino rotation
# Each 16-bit value represents a 4x4 grid, read left-to-right, top-to-bottom
$script:TetrominoBits = @{
    I = @(0x0F00, 0x2222, 0x00F0, 0x4444)  # Line piece
    O = @(0x6600, 0x6600, 0x6600, 0x6600)  # Square piece (all rotations same)
    T = @(0x4E00, 0x4640, 0x0E40, 0x4C40)  # T-piece
    S = @(0x6C00, 0x4620, 0x06C0, 0x8C40)  # S-piece
    Z = @(0xC600, 0x2640, 0x0C60, 0x4C80)  # Z-piece
    J = @(0x00E8, 0x0446, 0x02E0, 0x0C44)  # J-piece
    L = @(0x00E2, 0x0644, 0x08E0, 0x044C)  # L-piece
}

function Convert-BitsToPoint([int]$bits) {
    # Convert 16-bit pattern to array of Point coordinates
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
    # Convert 16-bit mask to 4-element array representing rows
    function ReverseNibble([int]$n) {
        # Reverse bit order: b3 b2 b1 b0 → b0 b1 b2 b3
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

# Initialize collision masks for fast bitboard operations
$global:TetrominoMasks = @{}
foreach ($id in $script:TetrominoBits.Keys) {
    $bitRotations = $script:TetrominoBits[$id]
    $expanded = @()
    foreach ($bits in $bitRotations) {
        $expanded += ,(Expand-Mask16ToArray $bits)
    }
    $global:TetrominoMasks[$id] = $expanded
}

# Initialize shapes as Point arrays for rendering
$global:TetrominoShapes = @{}
foreach ($id in $script:TetrominoBits.Keys) {
    $list = [System.Collections.Generic.List[Point[]]]::new()
    foreach ($b in $script:TetrominoBits[$id]) {
        $list.Add((Convert-BitsToPoint $b))
    }
    $global:TetrominoShapes[$id] = $list.ToArray()
}

# Calculate bounding dimensions for centering pieces
$global:TetrominoDims = @{}
foreach ($id in $global:TetrominoShapes.Keys) {
    $shape = $global:TetrominoShapes[$id][0]  # Use rotation 0 for dimensions
    $minX = $maxX = $shape[0].X
    $minY = $maxY = $shape[0].Y

    foreach ($p in $shape) {
        if ($p.X -lt $minX) { $minX = $p.X }
        if ($p.X -gt $maxX) { $maxX = $p.X }
        if ($p.Y -lt $minY) { $minY = $p.Y }
        if ($p.Y -gt $maxY) { $maxY = $p.Y }
    }

    $global:TetrominoDims[$id] = @{
        MinX   = $minX
        MaxX   = $maxX
        Width  = $maxX - $minX + 1
        MinY   = $minY
        MaxY   = $maxY
        Height = $maxY - $minY + 1
    }
}

# Super Rotation System (SRS) wall kick data
$global:TetrominoKicks = @{
    # Standard pieces (J, L, S, T, Z)
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

    # I-piece has different wall kick behavior
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

# Set script scope variables for backward compatibility
$script:TetrominoMasks = $global:TetrominoMasks
$script:TetrominoShapes = $global:TetrominoShapes
$script:TetrominoDims = $global:TetrominoDims
$script:TetrominoKicks = $global:TetrominoKicks