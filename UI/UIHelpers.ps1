# === UI HELPER FUNCTIONS ===

function LayoutTopStack($startX, $startY, $gap, [Panel[]]$panels) {
    $y = $startY
    foreach ($p in $panels) {
        $p.X = $startX
        $p.Y = $y
        $y += $p.Height + 2 + $gap  # frame border, +gap for spacing
    }
}

function Show-SplashScreen{param([ValidateRange(30,120)][int]$f=60)
[console]::Clear()
[console]::CursorVisible=$false
$o=[console]::Out
$s=[System.Diagnostics.Stopwatch]::new()
$r=[Random]::new()
$m=1000/$f
$a=@'
_|_|_|      _|                      _|    _|                _|            
_|    _|  _|_|_|_|    _|_|      _|_|_|  _|_|_|_|  _|  _|_|        _|_|_|  
_|    _|    _|      _|_|_|_|  _|    _|    _|      _|_|      _|  _|_|      
_|    _|    _|      _|        _|    _|    _|      _|        _|      _|_|  
_|_|_|        _|_|    _|_|_|    _|_|_|      _|_|  _|        _|  _|_|_|    
'@
$p='Press [Enter] to start'
$c=[char[]]" `'.,-~:;=!*#%$@&8BWM"
$k=@('Yellow','White','Magenta','Cyan','Gray') # ← sparkles!
$w=[console]::WindowWidth
$h=[console]::WindowHeight
if([console]::BufferWidth -lt $w -or [console]::BufferHeight -lt $h){[console]::SetBufferSize([math]::Max($w,[console]::BufferWidth),[math]::Max($h,[console]::BufferHeight))}
$l=$a-split"`n"
$hl=$l.Count
$wl=($l|Measure-Object Length -Max).Maximum
$y0=[int](($h-$hl)/2)
$x0=[int](($w-$wl)/2)
$yp=$y0+$hl+1
$xp=[int](($w-$p.Length)/2)
$b=[bool[]]::new($h)
$b[$yp]=$true
0..$hl|%{ $b[$y0+$_]=$true }
$d=New-Object 'System.Collections.Generic.List[ValueTuple[int,int,char]]'
for($i=0;$i -lt $hl;$i++){ $j=$l[$i];for($k1=0;$k1 -lt $j.Length;$k1++){ if($j[$k1]-ne''){ $null=$d.Add([ValueTuple]::Create($x0+$k1,$y0+$i,$j[$k1])) } } }
$nx=[double[,]]::new($h,$w);$ny=[double[,]]::new($h,$w)
for($y=0;$y -lt $h;$y++){ $ry=($y/$h)*2-1;for($x=0;$x -lt $w;$x++){ $nx[$y,$x]=(($x/$w)*2-1)*1.33;$ny[$y,$x]=$ry } }
$g=32;$gm=$g-1
$n=[double[][]]::new($g+1)
for($y=0;$y -le $g;$y++){ $n[$y]=[double[]]::new($g+1);for($x=0;$x -le $g;$x++){ $n[$y][$x]=$r.NextDouble() } }
$rb=[char[]]::new($w)
$a=0.0
while(-not([console]::KeyAvailable -and ([console]::ReadKey($true)).Key -eq 'Enter')){
$s.Restart()
$z=[math]::Pow(1.03,$a)
for($y=0;$y -lt $h;$y++){
if($b[$y]){[array]::Clear($rb,0,$w)}else{
for($x=0;$x -lt $w;$x++){
$fx=$nx[$y,$x]*$z*5
$fy=$ny[$y,$x]*$z*5
$x0=[int]$fx;$y0=[int]$fy;$sx=$fx-$x0;$sy=$fy-$y0
$ix0=$x0-band$gm;$iy0=$y0-band$gm
$ix1=($ix0+1)-band$gm;$iy1=($iy0+1)-band$gm
$v00=$n[$iy0][$ix0];$v10=$n[$iy0][$ix1]
$v01=$n[$iy1][$ix0];$v11=$n[$iy1][$ix1]
$m0=$v00+($v10-$v00)*$sx
$m1=$v01+($v11-$v01)*$sx
$v=$m0+($m1-$m0)*$sy
$i=[int]($v*($c.Length-1))
if($i -lt 0){$i=0}elseif($i -ge $c.Length){$i=$c.Length-1}
$rb[$x]=$c[$i]
}}
[console]::SetCursorPosition(0,$y)
if($w-gt 1){$o.Write($rb,0,$w)}
[console]::SetCursorPosition($w-1,$y)
$o.Write($rb[$w-1])
}
foreach($q in $d){[console]::SetCursorPosition($q.Item1,$q.Item2);[console]::ForegroundColor=$k[$r.Next($k.Count)];$o.Write($q.Item3)}
[console]::SetCursorPosition($xp,$yp);[console]::ForegroundColor='Gray';$o.Write($p);[console]::ResetColor()
$a+=0.05
$t=$m-$s.ElapsedMilliseconds
if($t -gt 0){Start-Sleep -ms ([int]$t)}
}
[console]::ResetColor();[console]::Clear()
}

function Show-GameOverScreen {
    $msg1 = 'GAME OVER'
    $msg2 = 'Press [R] to Restart or [Q] to Quit'

    $msgX1 = [int](([Console]::WindowWidth - $msg1.Length) / 2)
    $msgX2 = [int](([Console]::WindowWidth - $msg2.Length) / 2)
    $msgY  = [int](([Console]::WindowHeight) / 2)

    Write-CursorPositionIfChanged $msgX1 $msgY
    [Console]::Write($msg1)
    Write-CursorPositionIfChanged $msgX2 ($msgY + 1)
    [Console]::Write($msg2)
}

function Clear-GameOverScreen {
    $msg1 = 'GAME OVER'
    $msg2 = 'Press [R] to Restart or [Q] to Quit'

    $msgX1 = [int](([Console]::WindowWidth - $msg1.Length) / 2)
    $msgX2 = [int](([Console]::WindowWidth - $msg2.Length) / 2)
    $msgY  = [int](([Console]::WindowHeight) / 2)

    Write-CursorPositionIfChanged $msgX1 $msgY
    [Console]::Write(' ' * $msg1.Length)

    Write-CursorPositionIfChanged $msgX2 ($msgY + 1)
    [Console]::Write(' ' * $msg2.Length)
}