# === POINT CLASS ===

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

# Utility function for creating points
function P($x, $y) { 
    return [Point]::new([int]$x, [int]$y) 
}

# === CURSOR STATE TRACKING (for perf optimizations) ===
$script:LastCursorPosition = "-1:-1"

function Get-Idx($x, $y, $width) {
    return ($y * $width) + $x
}

function Write-CursorPositionIfChanged {
    param([int]$x, [int]$y)

    $posKey = "$($x):$($y)"

    if ($posKey -ne $script:LastCursorPosition) {
        [Console]::SetCursorPosition($x, $y)
        $script:LastCursorPosition = $posKey
    }
}