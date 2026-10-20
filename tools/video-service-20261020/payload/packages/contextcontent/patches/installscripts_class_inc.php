<?php
/** One managed video attachment per lesson placement. @author Derek Keats */
if(empty($GLOBALS['kewl_entry_point_run']))die('No direct access');
class contextcontent_installscripts extends dbTable
{
    public function postinstall($version=null)
    {
        $admin=$this->getObject('modulesadmin','modulecatalogue');$table='tbl_contextcontent_videos';
        $constraints=$admin->listTableConstraints($table);
        if(!is_array($constraints))throw new RuntimeException('Video placement constraint inspection failed');
        foreach(['contextvideo_identity'=>['id'=>[]],'contextvideo_placement'=>['placement_id'=>[]]] as $name=>$fields){
            if(!in_array($name,$constraints,true)&&$admin->createConstraint($table,$name,['unique'=>true,'fields'=>$fields])===false)throw new RuntimeException('Video placement constraint installation failed');
        }
    }
}
