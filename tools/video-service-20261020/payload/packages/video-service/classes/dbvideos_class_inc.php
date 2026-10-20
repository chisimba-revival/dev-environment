<?php
/** Managed video persistence. All SQL uses dbTable prepared APIs. @author Derek Keats */
if (empty($GLOBALS['kewl_entry_point_run'])) die('No direct access');
class dbvideos extends dbTable
{
    public function init($tableName=null,$pearDb=null,$errorCallback='globalPearErrorHandler') { parent::init('tbl_video_assets',$pearDb,$errorCallback); }
    public function one(string $id): ?array { return $this->selectPrepared('SELECT * FROM tbl_video_assets WHERE id=?',[$id])[0] ?? null; }
    public function save(string $id,array $values): void
    {
        $allowed=['scope','owner_id','title','description','provider','configuration','state','upload_id','asset_id','playback_id','metadata','error_code','updated_at'];
        $sets=[];$args=[];
        foreach($values as $key=>$value) { if(!in_array($key,$allowed,true)) throw new InvalidArgumentException('invalid_field'); $sets[]="$key=?";$args[]=$value; }
        if(!$sets)return; $args[]=$id;
        $this->executePrepared('UPDATE tbl_video_assets SET '.implode(',',$sets).' WHERE id=?',$args);
    }
    public function create(array $values): void
    {
        $this->executePrepared('INSERT INTO tbl_video_assets (id,scope,owner_id,title,description,provider,configuration,state,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?,?)',array_values($values));
    }
    public function listing(string $scope,string $search,int $offset): array
    {
        return $this->selectPrepared("SELECT * FROM tbl_video_assets WHERE scope=? AND state<>'deleted' AND title LIKE ? ORDER BY created_at DESC,id LIMIT 30 OFFSET ".max(0,$offset),[$scope,'%'.$search.'%']);
    }
    public function pending(): array { return $this->selectPrepared("SELECT * FROM tbl_video_assets WHERE state IN ('uploading','processing','pending_delete') ORDER BY updated_at LIMIT 50",[]); }
    public function forProvider(string $configuration,string $column,string $value): ?array
    {
        if(!in_array($column,['upload_id','asset_id'],true)||$value==='')return null;
        return $this->selectPrepared("SELECT * FROM tbl_video_assets WHERE configuration=? AND $column=?",[$configuration,$value])[0] ?? null;
    }
    public function eventSeen(string $configuration,string $id): bool { return !empty($this->selectPrepared('SELECT id FROM tbl_video_events WHERE configuration=? AND event_id=?',[$configuration,$id])); }
    public function rememberEvent(string $configuration,string $id): void { $this->executePrepared('INSERT INTO tbl_video_events (id,configuration,event_id,created_at) VALUES (?,?,?,?)',[bin2hex(random_bytes(16)),$configuration,$id,gmdate('Y-m-d H:i:s')]); }
    public function progress(string $user,string $reference,string $video): array
    {
        return $this->selectPrepared('SELECT * FROM tbl_video_progress WHERE user_id=? AND reference=? AND video_id=?',[$user,$reference,$video])[0] ?? ['position'=>0,'intervals'=>'[]','last_at'=>0,'last_position'=>0];
    }
    public function saveProgress(string $user,string $reference,string $video,array $progress): void
    {
        $this->executePrepared('INSERT INTO tbl_video_progress (id,user_id,reference,video_id,position,intervals,last_at,last_position) VALUES (?,?,?,?,?,?,?,?) ON DUPLICATE KEY UPDATE position=VALUES(position),intervals=VALUES(intervals),last_at=VALUES(last_at),last_position=VALUES(last_position)',
            [bin2hex(random_bytes(16)),$user,$reference,$video,$progress['position'],json_encode($progress['intervals']),$progress['last_at'],$progress['last_position']]);
    }
}
