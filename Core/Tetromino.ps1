# === TETROMINO CLASS ===

. "$PSScriptRoot\Point.ps1"
class Tetromino {
    [string]   $Id
    [int]      $Rotation = 0
    [int]      $X
    [int]      $Y
    [hashtable] $KickData

    Tetromino([string]$id, [int]$x, [int]$y, [hashtable]$kickData) {
        $this.Id        = $id
        $this.X         = $x
        $this.Y         = $y
        $this.KickData  = $kickData
    }

    [Point[]] GetBlocks() {
        $relBlocks = $global:TetrominoShapes[$this.Id][$this.Rotation % 4]
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