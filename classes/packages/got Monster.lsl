/*
    Script by toonie
    Modified by jas
*/
#define USE_EVENTS
#include "got/_core.lsl"

#define TIMER_FRAME "a"
#define TIMER_ATTACK "b" 



list PLAYERS;           // The players, should always contain owner
string chasetarg;       // Currently chased player

list ctData;            // Contains data about current target, see StatusMethod$get
vector lastseen;        // Position target was last seen at
vector rezpos;          // Position this was rezzed at. Used for roaming

integer STATE;          // Current movement state
#define STATE_IDLE 0
#define STATE_CHASING 1
#define STATE_SEEKING 2
 
integer FXFLAGS;
key look_override = ""; // Key to override looking at from current target

// Conf
float speed = 1;        // Movement speed, lower is faster
float hitbox = 3;       // Range of melee attacks
#define HITBOX_DEFAULT 1.5		// if hitbox is this value, use default
float atkspeed = 1;     // Time between melee attacks
float wander;           // Range to roam

integer RUNTIME_FLAGS;  // Flags that can be set from other script, see got Monster head file

integer BFL = 0x20;            // Don't roam unless a player is in range
#define BFL_IN_RANGE 0x1            // Monster is within attack range
#define BFL_MOVING 0x2              // Currently moving somewhere
#define BFL_ATTACK_CD 0x4           // Waiting for attack
#define BFL_DEAD 0x8                // Monster is dead
#define BFL_CHASING 0x10            // Chasing a target
#define BFL_PLAYERS_NEARBY 0x20     // LOD
#define BFL_INITIALIZED 0x40        // Script initialized
#define BFL_ANIMATOR_LOADED 0x80    // 
#define BFL_MANEUVERING 0x100       // Trying to go around a monster blocking the path

#define BFL_STOPON BFL_DEAD
 

integer moveInDir(vector dir){
    if(dir == ZERO_VECTOR)return FALSE;
    vector gpos = llGetPos();
    

    if(~RUNTIME_FLAGS&Monster$RF_IMMOBILE && ~FXFLAGS&fx$F_ROOTED){
        float sp = speed;
        if(~BFL&BFL_CHASING)sp/=2;

        dir = llVecNorm(dir)*.5*sp;
        list r = llCastRay((llGetPos()+dir+<0,0,1>), (llGetPos()+dir-<0,0,3>), ([RC_REJECT_TYPES, RC_REJECT_PHYSICAL|RC_REJECT_AGENTS, RC_DATA_FLAGS, RC_GET_ROOT_KEY]));
        if(llList2Integer(r, -1) <=0 || llVecDist(llGetPos()+dir+<0,0,1>, llList2Vector(r, 1))<.1){
            return FALSE;
        }
        if(~llSubStringIndex(prDesc(llList2Key(r,0)), "$M$"))return FALSE;
        vector z = llList2Vector(r, 1);
        llSetKeyframedMotion([z-gpos, .25/sp], [KFM_DATA, KFM_TRANSLATION]);
        toggleMove(TRUE);
    }else toggleMove(FALSE);
    
    if(~RUNTIME_FLAGS&Monster$RF_NOROT && ~FXFLAGS&fx$F_STUNNED)
        llLookAt(gpos+<dir.x, dir.y, 0>, 1, 1);
    return TRUE;
}


anim(string anim, integer start){
	integer meshAnim = (llGetInventoryType("ton MeshAnim") == INVENTORY_SCRIPT);
	if(start){
		if(meshAnim)MeshAnim$startAnim(anim);
		else MaskAnim$start(anim);
	}else{
		if(meshAnim)MeshAnim$stopAnim(anim);
		else MaskAnim$stop(anim);
	}
}

toggleMove(integer on){
    if(on && ~BFL&BFL_MOVING && ~BFL&BFL_STOPON && ~RUNTIME_FLAGS&Monster$RF_IMMOBILE){
        BFL = BFL|BFL_MOVING;
        anim("walk", true);
    }else if(!on && BFL&BFL_MOVING){
        BFL = BFL&~BFL_MOVING;
        anim("walk", false);
        llSetKeyframedMotion([], [KFM_COMMAND, KFM_CMD_STOP]);
    }
}

#define updateLookAt() \
	if(~RUNTIME_FLAGS&Monster$RF_NOROT || FXFLAGS&fx$F_STUNNED){ \
		vector pp = prPos(chasetarg); \
		vector gpos = llGetPos(); \
		if(look_override)pp = prPos(look_override); \
		llLookAt(<pp.x, pp.y, gpos.z>,1,1); \
	}\


timerEvent(string id, string data){
    if(id == TIMER_FRAME){
        if(BFL&BFL_STOPON || FXFLAGS&fx$F_STUNNED)return;
        
        // Try to find a target
        if(STATE == STATE_IDLE){
            if(RUNTIME_FLAGS&Monster$RF_IMMOBILE || FXFLAGS&fx$F_ROOTED)return;
            
            // Find a random pos to go to maybe
            if(wander == 0 || llFrand(1)>.1 || ~BFL&BFL_PLAYERS_NEARBY)return;
			
            vector a = llGetPos()+<0,0,.5>;
            vector b = llGetPos()+<0,0,.5>+llVecNorm(<llFrand(2)-1,llFrand(2)-1,0>)*llFrand(wander);
            
			if(llVecDist(b, rezpos)>wander)return;
            list ray = llCastRay(a, b, []);
            if(llList2Integer(ray, -1) == 0){
                lastseen = b;
                STATE = STATE_SEEKING;
            }
        } 
        
        
        else if(STATE == STATE_SEEKING){
            if(RUNTIME_FLAGS&Monster$RF_IMMOBILE || FXFLAGS&fx$F_ROOTED)return;
            
            vector gpos = llGetPos();
            if(BFL & BFL_PLAYERS_NEARBY && llVecDist(<lastseen.x, lastseen.y, 0>, <gpos.x, gpos.y, 0>)>=hitbox/2){
                list ray = llCastRay(llGetPos()+<0,0,1>, lastseen, []);
                
                if(llList2Integer(ray, -1)==0){
                    moveInDir(llVecNorm(lastseen-llGetPos()));
                    return;
                }
            }
            if(BFL&BFL_MANEUVERING){
                BFL = BFL&~BFL_MANEUVERING;
                STATE = STATE_CHASING;
                return;
            }
            STATE = STATE_IDLE;
            toggleMove(FALSE);
            lastseen = ZERO_VECTOR;
            BFL = BFL&~BFL_CHASING;
        }
        
		// Tracking a player
        else if(STATE == STATE_CHASING){
            BFL = BFL|BFL_CHASING;
			
            vector ppos = prPos(chasetarg);
            
            // Player left sim
            if(ppos == ZERO_VECTOR){
                STATE = STATE_IDLE;
                Status$dropAggro(chasetarg);
                
                // raiseEvent(MonsterEvt$lostTarget, chasetarg);
                chasetarg = "";
                toggleMove(FALSE);
                return;
            }
            
            // Close enough to attack
			if(llVecDist(ppos, llGetPos())<=hitbox){
				if(~BFL&BFL_IN_RANGE){
                    raiseEvent(MonsterEvt$inRange, chasetarg);
                }

				// This is where we request an attack
				if(
					atkspeed>0 && 
					~BFL&BFL_ATTACK_CD &&
					BFL&BFL_IN_RANGE && 
					~BFL&BFL_STOPON && 
					~FXFLAGS&(fx$F_PACIFIED|fx$F_STUNNED) && 
					~RUNTIME_FLAGS&Monster$RF_PACIFIED && 
					llList2Integer(llCastRay(llGetPos()+<0,0,.5>, prPos(chasetarg), [RC_REJECT_TYPES, RC_REJECT_AGENTS|RC_REJECT_PHYSICAL]), -1) == 0
				){
					Status$get(chasetarg, "ATK");
				}
				
                BFL = BFL|BFL_IN_RANGE;
			}else{
				if(BFL&BFL_IN_RANGE){
                    raiseEvent(MonsterEvt$lostRange, chasetarg);
                    BFL = BFL&~BFL_IN_RANGE;
                }
			}
			
			// Stop moving at half the hitbox
            if(llVecDist(ppos, llGetPos())<=hitbox/2){
                updateLookAt();
				toggleMove(FALSE);
            }
            // Might be in range but should move closer
            else{
				
			
                vector add = <0,0,1>;
                if(llGetAgentInfo(chasetarg)&AGENT_CROUCHING)add = ZERO_VECTOR;
                
                list ray = llCastRay(llGetPos()+add, ppos+add, ([RC_REJECT_TYPES, RC_REJECT_PHYSICAL|RC_REJECT_AGENTS, RC_DATA_FLAGS, RC_GET_ROOT_KEY]));

                if(llList2Integer(ray, -1)>0){
                    if(RUNTIME_FLAGS&Monster$RF_FREEZE_AGGRO)return;
                    string desc = prDesc(llList2Key(ray, 0));
                    Status$dropAggro(chasetarg);                
                    STATE = STATE_SEEKING;
                    // dropAggro()
                    //raiseEvent(MonsterEvt$lostTarget, chasetarg);
                }else{
                    lastseen = ppos;
                    // move towards player
                    moveInDir(llVecNorm(ppos-llGetPos()));
                }
            }
        }
        
    }
	// Timer run after an attack
    else if(id == TIMER_ATTACK){
		// Set it so we can attack again
		BFL = BFL&~BFL_ATTACK_CD;
    }
}


onEvt(string script, integer evt, string data){
    if(script == "got Portal" && evt == evt$SCRIPT_INIT){
        rezpos = llGetPos();
        PLAYERS = llJson2List(data);
        LocalConf$ini();
    }
    
    else if(script == "got FXCompiler" && evt == FXCEvt$update){
		FXFLAGS = (integer)j(data, 0);
		if(FXFLAGS&(fx$F_STUNNED|fx$F_ROOTED))toggleMove(FALSE);
    }
    
    else if(script == "got LocalConf" && evt == LocalConfEvt$iniData){

        list conf = llJson2List(data);
		string override = portalConf();
		if(isset(override)){
			list data = llJson2List(override);
			override = "";
			list_shift_each(data, v,
				list d = llJson2List(v);
				if(llGetListEntryType(d, 0) == TYPE_INTEGER)
					conf = llListReplaceList(conf, llList2List(d,1,1), llList2Integer(d,0), llList2Integer(d,0));
			)
		}
        RUNTIME_FLAGS = llList2Integer(conf, 0);
        if(llList2Float(conf,1)>0)speed = llList2Float(conf, 1);
		if(llList2Float(conf, 2) != HITBOX_DEFAULT)
			hitbox = llList2Float(conf, 2);
        atkspeed = llList2Float(conf, 3);
        if(llList2Float(conf,5)!=0)wander = llFabs(llList2Float(conf, 5));
           
        if(speed<=0)speed = 1;
        if(hitbox<=0)hitbox = 3;
        //if(atkspeed<.5)atkspeed = .5;
		
        BFL = BFL|BFL_INITIALIZED; 
        multiTimer([TIMER_FRAME, "", .25, TRUE]);
        llSetObjectDesc("$M$");
    }
    
    else if(((script == "ton MeshAnim" || script == "jas MaskAnim") && evt == MeshAnimEvt$frame) || (script == "got LocalConf" && evt==LocalConfEvt$emulateAttack)){
        
		list split = llParseString2List(data, [";"], []);
        string task = llList2String(split, 0);
        
        if(task == FRAME_AUDIO)llPlaySound(llList2String(split,1), llList2Float(split,2));
        else if(task == Monster$atkFrame || (script == "got LocalConf" && evt == LocalConfEvt$emulateAttack)){
            list odata = llGetPrimitiveParams([PRIM_POSITION, PRIM_ROTATION]);
            list ifdata = llGetObjectDetails(chasetarg, [OBJECT_POS, OBJECT_ROT]);
            vector pos = llList2Vector(odata,0);
            vector dpos = llList2Vector(ifdata, 0);
            
            if(~RUNTIME_FLAGS&Monster$RF_NOROT && chasetarg != "")
                llLookAt(<dpos.x, dpos.y, pos.z>, 1,1);
            
            float dist = llVecDist(pos, dpos);
            if(dist>hitbox*2)return;
            
            raiseEvent(MonsterEvt$attack, mkarr([chasetarg]));
        }
        
    }
    
    else if(script == "got Status"){
        if(evt == StatusEvt$dead){
            if(~BFL&BFL_DEAD && (integer)data){
                BFL = BFL|BFL_DEAD;
                toggleMove(FALSE);
            }
        }else if(evt == StatusEvt$monster_gotTarget){
            if(BFL&BFL_STOPON)return;
            if(jVal(data, [0]) != ""){
                chasetarg = jVal(data, [0]);
                STATE = STATE_CHASING;
            }
			/* You are probably seeking
			else{
                STATE = STATE_IDLE;
                toggleMove(FALSE);
            }
			*/
        }
    }
    
    else if(script == "jas MaskAnim" || script == "ton MeshAnim"){
        if(evt == MeshAnimEvt$agentsInRange)
            BFL = BFL|BFL_PLAYERS_NEARBY;    
        else if(evt == MeshAnimEvt$agentsLost)
            BFL = BFL&~BFL_PLAYERS_NEARBY;
    }

}

default
{
    on_rez(integer rawr){llResetScript();}
    
    timer(){multiTimer([]);}
    
    state_entry(){
		llSetStatus(STATUS_PHANTOM, TRUE);
        PLAYERS = [(string)llGetOwner()];
        if(llGetStartParameter())raiseEvent(evt$SCRIPT_INIT, "");
    }

    #define LISTEN_LIMIT_LINK LINK_THIS
    #define LISTEN_LIMIT_FREETEXT if(llListFindList(PLAYERS, [(string)llGetOwnerKey(id)]) == -1)return;
    #include "xobj_core/_LISTEN.lsl"
    
    #include "xobj_core/_LM.lsl" 
    /*
        Included in all these calls: 
        METHOD - (int)method  
        INDEX - (int)obj_index   
        PARAMS - (var)parameters 
        SENDER_SCRIPT - (var)parameters
        CB - The callback you specified when you sent a task 
    */ 
    if(method$isCallback){ 
        if(METHOD == StatusMethod$get && id!="" && SENDER_SCRIPT == "got Status"){
            ctData = llJson2List(PARAMS);
            if(CB == "ATK" && ~BFL&BFL_ATTACK_CD){
                multiTimer([TIMER_ATTACK, "", atkspeed+llFrand(atkspeed*.5), FALSE]);
				if(BFL&BFL_STOPON || RUNTIME_FLAGS&Monster$RF_PACIFIED || FXFLAGS&(fx$F_PACIFIED|fx$F_STUNNED))return;
				integer flags = llList2Integer(ctData, 0);
				if(!_attackable(PARAMS))return; 
				
				raiseEvent(MonsterEvt$attackStart, mkarr([chasetarg]));
				BFL = BFL|BFL_ATTACK_CD;
				
				anim("attack", TRUE);
			}
            
        } 
        return;  
    }
    
    // Public
    if(METHOD == MonsterMethod$toggleFlags){
        integer pre = RUNTIME_FLAGS;
        RUNTIME_FLAGS = RUNTIME_FLAGS|(integer)method_arg(0);
        RUNTIME_FLAGS = RUNTIME_FLAGS&~(integer)method_arg(1);
        
        
        raiseEvent(MonsterEvt$runtimeFlagsChanged, (string)RUNTIME_FLAGS);
        if(RUNTIME_FLAGS&Monster$RF_IMMOBILE){
            toggleMove(FALSE);
        }  
        if(pre&Monster$RF_NOROT && RUNTIME_FLAGS&Monster$RF_NOROT){
            llStopLookAt();
        }
    }
    else if(METHOD == MonsterMethod$lookOverride){
		look_override = method_arg(0);
		updateLookAt();
	}
	else if(METHOD == MonsterMethod$atkspeed)atkspeed = (float)method_arg(0);
    #define LM_BOTTOM  
    #include "xobj_core/_LM.lsl"   
}
