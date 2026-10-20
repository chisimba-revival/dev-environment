<?php
/** ContextContent owns video placement, visibility and stage requirements. @author Derek Keats */
if (empty($GLOBALS['kewl_entry_point_run'])) die('No direct access');
class videoconsumer extends dbTable
{
    public function init($tableName=null,$pearDb=null,$errorCallback='globalPearErrorHandler'){parent::init('tbl_contextcontent_videos',$pearDb,$errorCallback);}
    public function mayManage(string $context): bool
    {
        $user=$this->getObject('user','security');$course=$this->getObject('dbcontext','context')->getContext($context);
        return !empty($course) && $user->isLoggedIn() && ($user->isAdmin() || $user->isContextLecturer($user->userId(),$context));
    }
    public function link(string $id): ?array {return $this->selectPrepared('SELECT * FROM tbl_contextcontent_videos WHERE id=?',[$id])[0] ?? null;}
    public function placement(string $id): ?array {return $this->selectPrepared('SELECT * FROM tbl_contextcontent_videos WHERE placement_id=?',[$id])[0] ?? null;}
    public function references(string $video): array {return $this->selectPrepared('SELECT * FROM tbl_contextcontent_videos WHERE video_id=?',[$video]);}
    public function mayPlay(string $reference,string $video): bool
    {
        $link=$this->link($reference);if(!$link||$link['video_id']!==$video)return false;
        $page=$this->getObject('db_contextcontent_order','contextcontent')->getPage($link['placement_id'],$link['contextcode']);if(!$page)return false;
        if($this->mayManage($link['contextcode']))return true;
        $user=$this->getObject('user','security');$course=$this->getObject('dbcontext','context')->getContext($link['contextcode']);
        if(!$user->isLoggedIn()||!$course||strtolower($course['status'] ?? '')!=='published'||!$this->getObject('usercontext','context')->isContextMember($user->userId(),$link['contextcode']))return false;
        $rows=$this->selectPrepared("SELECT o.id FROM tbl_contextcontent_order o INNER JOIN tbl_contextcontent_chaptercontext c ON c.contextcode=o.contextcode AND c.chapterid=o.chapterid WHERE o.id=? AND o.contextcode=? AND o.visibility='Y' AND c.visibility='Y'",[$link['placement_id'],$link['contextcode']]);
        return !empty($rows) && $this->getObject('chapterstagegateservice','contextcontent')->entryDecision($link['contextcode'],$page['chapterid'])['allowed'];
    }
    public function attach(string $context,string $placement,string $video,int $percent): void
    {
        if(!$this->mayManage($context)||$percent<0||$percent>100)throw new RuntimeException('access_denied');
        if(!$this->getObject('db_contextcontent_order','contextcontent')->getPage($placement,$context))throw new RuntimeException('not_found');
        $service=$this->getObject('videoservice','video-service');$service->managed($video);
        $service->db->withDatabaseLock('video-service',function()use($context,$placement,$video,$percent,$service){
            $asset=$service->db->one($video);if(!$asset||$asset['scope']!=='contextcontent:'.$context||in_array($asset['state'],['deleted','pending_delete'],true))throw new RuntimeException('access_denied');
            $existing=$this->placement($placement);if($existing && $existing['video_id']!==$video)throw new RuntimeException('attachment_exists');
            $this->executePrepared('INSERT INTO tbl_contextcontent_videos (id,contextcode,placement_id,video_id,required_percent) VALUES (?,?,?,?,?) ON DUPLICATE KEY UPDATE video_id=VALUES(video_id),required_percent=VALUES(required_percent)',[bin2hex(random_bytes(16)),$context,$placement,$video,$percent]);
        });
    }
    public function detach(string $reference): void
    {
        $link=$this->link($reference);if(!$link||!$this->mayManage($link['contextcode']))throw new RuntimeException('access_denied');
        $this->withDatabaseLock('video-service',function()use($reference){$this->executePrepared('DELETE FROM tbl_contextcontent_videos WHERE id=?',[$reference]);});
    }
    /** Completion uses stored playback evidence; it does not depend on provider identifiers. */
    public function chapterRequirement(string $context,string $chapter,?string $userId=null): array
    {
        $links=$this->selectPrepared("SELECT v.* FROM tbl_contextcontent_videos v INNER JOIN tbl_contextcontent_order o ON o.id=v.placement_id AND o.contextcode=v.contextcode WHERE v.contextcode=? AND o.chapterid=? AND o.visibility='Y' AND v.required_percent>0",[$context,$chapter]);
        if(!$links)return ['required'=>false,'complete'=>true,'percent'=>100];
        if(!$this->getObject('modules','modulecatalogue')->checkIfRegistered('video-service'))return ['required'=>true,'complete'=>false,'percent'=>0];
        $userId=$userId ?? (string)$this->getObject('user','security')->userId();$db=$this->getObject('dbvideos','video-service');$this->getObject('videoprogress','video-service');$complete=true;$minimum=100;
        foreach($links as $link){$video=$db->one($link['video_id']);$duration=(float)(json_decode($video['metadata'] ?? '{}',true)['duration'] ?? 0);$percent=videoprogress::percentage($db->progress($userId,'contextcontent:'.$link['id'],$link['video_id']),$duration);$minimum=min($minimum,$percent);if($percent+0.001<(int)$link['required_percent'])$complete=false;}
        return ['required'=>true,'complete'=>$complete,'percent'=>$minimum];
    }
}
