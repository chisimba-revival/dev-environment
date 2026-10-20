<?php
/** Bounded playback evidence, distinct from course completion. @author Derek Keats */
if (empty($GLOBALS['kewl_entry_point_run'])) die('No direct access');
class videoprogress extends ChisimbaObject
{
    public static function advance(array $old,float $position,float $duration,int $now,bool $playing): array
    {
        if(!is_finite($position)||!is_finite($duration)||$duration<=0||$position<0||$position>$duration+1) throw new RuntimeException('invalid_progress');
        $position=min($duration,$position);$intervals=json_decode($old['intervals'] ?? '[]',true) ?: [];
        $delta=$position-(float)($old['last_position'] ?? 0);$elapsed=$now-(int)($old['last_at'] ?? 0);
        // First report establishes a baseline. Seeks, stale reports and long gaps earn no credit.
        if($playing && $elapsed>0 && $elapsed<=30 && $delta>0 && $delta<=min(30,$elapsed*2+1)) $intervals[]=[(float)$old['last_position'],$position];
        usort($intervals,static fn($a,$b)=>$a[0]<=>$b[0]);$merged=[];
        foreach($intervals as $range){$i=count($merged)-1;if($i>=0&&$range[0]<=$merged[$i][1]+0.1)$merged[$i][1]=max($merged[$i][1],$range[1]);else $merged[]=$range;}
        if(count($merged)>4000)throw new RuntimeException('invalid_progress');
        return ['position'=>$position,'intervals'=>$merged,'last_at'=>$now,'last_position'=>$position];
    }
    public static function percentage(array $progress,float $duration): float
    {
        if($duration<=0)return 0;$ranges=is_array($progress['intervals'] ?? null)?$progress['intervals']:(json_decode($progress['intervals'] ?? '[]',true) ?: []);
        return min(100,100*array_sum(array_map(static fn($r)=>max(0,$r[1]-$r[0]),$ranges))/$duration);
    }
}
