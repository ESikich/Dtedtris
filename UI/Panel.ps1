# === PANEL BASE CLASS ===

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

        $topLeft = [char]0x250C
        $topRight = [char]0x2510
        $bottomLeft = [char]0x2514
        $bottomRight = [char]0x2518
        $horizontal = [char]0x2500
        $vertical = [char]0x2502

        $frameTop = "$topLeft" + ("$horizontal" * $this.Width) + "$topRight"

        if ($this.Title) {
            $titleString = " $($this.Title) "
            $mid = [math]::Floor(($this.Width - $titleString.Length) / 2)
            $frameTop = "$topLeft" + ("$horizontal" * $mid) + $titleString + ("$horizontal" * ($this.Width - $mid - $titleString.Length)) + "$topRight"
        }

        Write-CursorPositionIfChanged $this.X $this.Y
        [Console]::Write($frameTop)

        for ($row = 0; $row -lt $this.Height; $row++) {
            Write-CursorPositionIfChanged $this.X ($this.Y + 1 + $row)
            [Console]::Write("$vertical")
            Write-CursorPositionIfChanged ($this.X + $this.Width + 1) ($this.Y + 1 + $row)
            [Console]::Write("$vertical")
        }

        Write-CursorPositionIfChanged $this.X ($this.Y + $this.Height + 1)
        [Console]::Write("$bottomLeft" + ("$horizontal" * $this.Width) + "$bottomRight")
    }

    static [hashtable] GetMinMax([Point[]]$arr) {
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
}
