# === TETROMINO DATA MANAGEMENT ===

class TetrominoDataManager {
    [hashtable] $BitPatterns
    [hashtable] $Shapes
    [hashtable] $Masks
    [hashtable] $Dimensions
    [hashtable] $WallKicks

    TetrominoDataManager() {
        $this.InitializeBitPatterns()
        $this.BuildShapes()
        $this.BuildMasks()
        $this.CalculateDimensions()
        $this.InitializeWallKicks()
    }

    [void] InitializeBitPatterns() {
        # 16-bit patterns for each tetromino rotation
        # Each bit represents a 4x4 grid cell, read left-to-right, top-to-bottom
        $this.BitPatterns = @{
            I = @(0x0F00, 0x2222, 0x00F0, 0x4444)  # Line piece
            O = @(0x6600, 0x6600, 0x6600, 0x6600)  # Square piece (all rotations same)
            T = @(0x4E00, 0x4640, 0x0E40, 0x4C40)  # T-piece
            S = @(0x6C00, 0x4620, 0x06C0, 0x8C40)  # S-piece
            Z = @(0xC600, 0x2640, 0x0C60, 0x4C80)  # Z-piece
            J = @(0x00E8, 0x0446, 0x02E0, 0x0C44)  # J-piece
            L = @(0x00E2, 0x0644, 0x08E0, 0x044C)  # L-piece
        }
    }

    [void] BuildShapes() {
        $this.Shapes = @{}
        foreach ($id in $this.BitPatterns.Keys) {
            $rotations = @()
            foreach ($bits in $this.BitPatterns[$id]) {
                $rotations += ,$this.ConvertBitsToPoints($bits)
            }
            $this.Shapes[$id] = $rotations
        }
    }

    [void] BuildMasks() {
        $this.Masks = @{}
        foreach ($id in $this.BitPatterns.Keys) {
            $maskRotations = @()
            foreach ($bits in $this.BitPatterns[$id]) {
                $maskRotations += ,$this.ExpandBitsTo4x4Array($bits)
            }
            $this.Masks[$id] = $maskRotations
        }
    }

    [void] CalculateDimensions() {
        $this.Dimensions = @{}
        foreach ($id in $this.Shapes.Keys) {
            # Use rotation 0 for dimension calculation
            $shape = $this.Shapes[$id][0]
            $bounds = $this.GetBoundingBox($shape)
            
            $this.Dimensions[$id] = @{
                MinX   = $bounds.MinX
                MaxX   = $bounds.MaxX
                Width  = $bounds.MaxX - $bounds.MinX + 1
                MinY   = $bounds.MinY
                MaxY   = $bounds.MaxY
                Height = $bounds.MaxY - $bounds.MinY + 1
            }
        }
    }

    [void] InitializeWallKicks() {
        # Super Rotation System (SRS) wall kick data
        $this.WallKicks = @{
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
    }

    [Point[]] ConvertBitsToPoints([int]$bits) {
        # Convert 16-bit pattern to array of Point coordinates
        $points = @()
        for ($i = 0; $i -lt 16; $i++) {
            if ($bits -band (1 -shl (15 - $i))) {
                $x = $i % 4
                $y = [math]::Floor($i / 4)
                $points += [Point]::new($x, $y)
            }
        }
        return $points
    }

    [int[]] ExpandBitsTo4x4Array([int]$mask16) {
        # Convert 16-bit mask to 4-element array representing rows
        # Each array element contains a 4-bit value for that row
        $rows = @(0, 0, 0, 0)
        
        for ($row = 0; $row -lt 4; $row++) {
            $rowBits = ($mask16 -shr (12 - $row * 4)) -band 0xF
            # Reverse bit order to match game coordinate system
            $rows[$row] = $this.ReverseBits($rowBits, 4)
        }
        
        return $rows
    }

    [int] ReverseBits([int]$value, [int]$bitCount) {
        # Reverse the order of bits in a value
        $result = 0
        for ($i = 0; $i -lt $bitCount; $i++) {
            if ($value -band (1 -shl $i)) {
                $result = $result -bor (1 -shl ($bitCount - 1 - $i))
            }
        }
        return $result
    }

    [hashtable] GetBoundingBox([Point[]]$points) {
        # Calculate minimum bounding rectangle for a set of points
        if (-not $points -or $points.Count -eq 0) {
            return @{ MinX = 0; MaxX = 0; MinY = 0; MaxY = 0 }
        }

        $minX = $maxX = $points[0].X
        $minY = $maxY = $points[0].Y
        
        foreach ($point in $points) {
            if ($point.X -lt $minX) { $minX = $point.X }
            if ($point.X -gt $maxX) { $maxX = $point.X }
            if ($point.Y -lt $minY) { $minY = $point.Y }
            if ($point.Y -gt $maxY) { $maxY = $point.Y }
        }
        
        return @{ MinX = $minX; MaxX = $maxX; MinY = $minY; MaxY = $maxY }
    }

    [hashtable] GetAllData() {
        # Return all computed data for use by other systems
        return @{
            Shapes = $this.Shapes
            Masks = $this.Masks
            Dimensions = $this.Dimensions
            WallKicks = $this.WallKicks
        }
    }
}

# Initialize the tetromino data
$TetrominoData = [TetrominoDataManager]::new()
$AllTetrominoData = $TetrominoData.GetAllData()

# Set global variables for backward compatibility
$global:TetrominoShapes = $AllTetrominoData.Shapes
$global:TetrominoMasks = $AllTetrominoData.Masks
$global:TetrominoDims = $AllTetrominoData.Dimensions
$global:TetrominoKicks = $AllTetrominoData.WallKicks

# Also set script scope variables
$script:TetrominoShapes = $global:TetrominoShapes
$script:TetrominoMasks = $global:TetrominoMasks
$script:TetrominoDims = $global:TetrominoDims
$script:TetrominoKicks = $global:TetrominoKicks

# Update the global config with tetromino data
if ($Global:GameConfig) {
    $Global:GameConfig.SetTetrominoData(
        $AllTetrominoData.Dimensions,
        $AllTetrominoData.Masks,
        $AllTetrominoData.WallKicks
    )
}