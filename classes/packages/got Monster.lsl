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

list SEEKTARG;			// [(var)targ, (float)range, (str)callback] Target received from MonsterMethod$seek, either a vector or a key
list ctData;            // Contains data about current target, see StatusMethod$get
vector lastseen;        // Position target was last seen at
vector rezpos;          // Position this was rezzed at. Used for roaming

integer STATE;          // Current movement state

#define dout(text) llSetText((str)(text), <1,1,1>, 1)

integer FXFLAGS;
key look_override = ""; // Key to override looking at from current target

// Conf
float speed = 1;        // Movement speed, lower is faster
float hitbox = 3;       // Range of melee attacks
#define HITBOX_DEFAULT 1.5		// if hitbox is this value, use default
float atkspeed = 1;     // Time between melee attacks
float wander;           // Range to roam

integer height_add;		// LOS check height offset from the default 0.5m above root prim
#define hAdd() ((float)height_add/10)

float fxSpeed = 1;			// FX speed modifier
float fxCooldownMod = 1;	// Used for attack speed

integer RUNTIME_FLAGS;  		// Flags that can be set from other script, see got Monster head file
integer RUNTIME_FLAGS_SPELL;	// Flags set from npcspells

#define getRF() (RUNTIME_FLAGS|RUNTIME_FLAGS_SPELL)

integer BFL = 0x20;            // Don't roam unless a player is in range
#define BFL_IN_RANGE 0x1            // Monster is within attack range
#define BFL_MOVING 0x2              // Currently moving somewhere
#define BFL_ATTACK_CD 0x4           // Waiting for attack
#define BFL_DEAD 0x8                // Monster is dead
#define BFL_CHASING 0x10            // Chasing a target
#define BFL_PLAYERS_NEARBY 0x20     // LOD
#define BFL_INITIALIZED 0x40        // Script initialized
#define BFL_SEEKING 0x80			// Seeking a target received by MonsterMethod$seek
//#define BFL_ANIMATOR_LOADED 0x80    // 
//#define BFL_MANEUVERING 0x100       // Trying to go around a monster blocking the path


#define BFL_STOPON BFL_DEAD
 
#define getSpeed() (speed*fxSpeed)
#define setState(n) STATE = n; raiseEvent(MonsterEvt$state, (str)STATE)

integer moveInDir(vector dir){
	if(dir == ZERO_VECTOR)return FALSE;
    dir = llVecNorm(dir);
	vector gpos = llGetPos();
    
	float sp = getSpeed();
    if(~getRF()&Monster$RF_IMMOBILE && ~FXFLAGS&fx$F_ROOTED && sp>0){
        
        if(~BFL&BFL_CHASING && ~BFL&BFL_SEEKING)sp/=2;

        dir = dir*sp;
		vector a = <0,0,0.5+hAdd()>;	// Max climb distance
		vector b = <0,0,-1>;	// Max drop distance
		// If flying, go directly towards the target 
		if(getRF()&Monster$RF_FLYING){
			a = b = ZERO_VECTOR;
		}
		
		
		
		// Vertical raycast
		vector rayStart = gpos+a;
		// movement, hAdd() is not added
        list r = llCastRay(rayStart, gpos+dir+b, [RC_REJECT_TYPES, RC_REJECT_PHYSICAL|RC_REJECT_AGENTS, RC_DATA_FLAGS, RC_GET_ROOT_KEY]);
        vector hit = l2v(r, 1);
		
		//dout(llVecDist(rayStart, hit));
		if(
			// Too steep drop
			(~getRF()&Monster$RF_FLYING && llList2Integer(r, -1) <=0)
		){
            toggleMove(FALSE);
			return FALSE;
        }
        /*
		if(~llSubStringIndex(prDesc(llList2Key(r,0)), "$M$"))
			return FALSE;
        */
		
		vector z = llList2Vector(r, 1);
		if(getRF()&Monster$RF_FLYING)
			z = gpos+dir;
			
        llSetKeyframedMotion([z-gpos, .25/sp], [KFM_DATA, KFM_TRANSLATION]);
        toggleMove(TRUE);
    }else toggleMove(FALSE);
    
    if(~getRF()&Monster$RF_NOROT && ~FXFLAGS&fx$F_STUNNED && (look_override == "" || look_override == NULL_KEY))
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
    if(on && ~BFL&BFL_MOVING && ~BFL&BFL_STOPON && ~getRF()&Monster$RF_IMMOBILE){
        BFL = BFL|BFL_MOVING;
        anim("walk", true);
    }else if(!on && BFL&BFL_MOVING){
        BFL = BFL&~BFL_MOVING;
        anim("walk", false);
        llSetKeyframedMotion([], [KFM_COMMAND, KFM_CMD_STOP]);
    }
}

#define updateLookAt() \
	if(~getRF()&Monster$RF_NOROT && ~FXFLAGS&fx$F_STUNNED){ \
		vector pp = prPos(chasetarg); \
		vector gpos = llGetPos(); \
		if(look_override)pp = prPos(look_override); \
		llLookAt(<pp.x, pp.y, gpos.z>,1,1); \
	}\


timerEvent(string id, string data){
    if(id == TIMER_FRAME){
        if(BFL&BFL_STOPON || FXFLAGS&fx$F_STUNNED)return;
        
        // Try to find a target
        if(STATE == MONSTER_STATE_IDLE){
            if(getRF()&(Monster$RF_IMMOBILE|Monster$RF_FOLLOWER) || FXFLAGS&fx$F_ROOTED)return;
            
			//llSetLinkPrimitiveParamsFast(2, [PRIM_TEXT, (str)wander+"\n"+portalConf$desc, <1,1,1>, 1]);
            // Find a random pos to go to maybe
            if(wander == 0 || llFrand(1)>.1 || ~BFL&BFL_PLAYERS_NEARBY)return;
			
            vector a = llGetPos()+<0,0,.5>;
            vector b = llGetPos()+<0,0,.5>+llVecNorm(<llFrand(2)-1,llFrand(2)-1,0>)*llFrand(wander);
            
			if(llVecDist(b, rezpos)>wander)return;
			
			// Movement, hAdd() is not added
            list ray = llCastRay(a, b, []);
            if(llList2Integer(ray, -1) == 0){
                lastseen = b;
				setState(MONSTER_STATE_SEEKING);
            }
        } 
        
        
        else if(STATE == MONSTER_STATE_SEEKING){
            if(getRF()&Monster$RF_IMMOBILE || FXFLAGS&fx$F_ROOTED)return;
            if(getRF()&Monster$RF_FOLLOWER){	// Followers can't seek
				setState(MONSTER_STATE_IDLE);
				return;
			}
			
			vector gpos = llGetPos();
			
			float md = 0.1;				// Min dist to be considered at target
			vector t = lastseen;		// Pos to go to
			if(SEEKTARG){ // External defined target
				t = l2v(SEEKTARG, 0);
				md = l2f(SEEKTARG, 1);
				if(llGetListEntryType(SEEKTARG, 0) != TYPE_VECTOR)
					t = prPos(l2s(SEEKTARG,0));
			}
					
			float dist = llVecDist(<t.x, t.y, 0>, <gpos.x, gpos.y, 0>);
            if(BFL & BFL_PLAYERS_NEARBY && dist>md && t != ZERO_VECTOR){
			
				// Movement, hAdd() not added
                list ray = llCastRay(llGetPos()+<0,0,1>, t+<0,0,1>, [RC_DATA_FLAGS, RC_GET_ROOT_KEY, RC_REJECT_TYPES, RC_REJECT_AGENTS|RC_REJECT_PHYSICAL]);
                
                if(llList2Integer(ray, -1)==0 || l2k(ray, 0) == l2k(SEEKTARG, 0)){
                    if(moveInDir(t-gpos))
						return;
                }
            }
			if(SEEKTARG){
				BFL = BFL&~BFL_SEEKING;
				if(dist<md){
					raiseEvent(MonsterEvt$seekComplete, l2s(SEEKTARG, 2));
				}
				else{
					raiseEvent(MonsterEvt$seekFail, l2s(SEEKTARG, 2));
				}
				SEEKTARG = [];
			}
			
			integer s = MONSTER_STATE_IDLE;
			if(chasetarg){
				s = MONSTER_STATE_CHASING;
			}
			setState(s);
            
			toggleMove(FALSE);
            lastseen = ZERO_VECTOR;
            BFL = BFL&~BFL_CHASING;
			
        }
        
		// Tracking a player
        else if(STATE == MONSTER_STATE_CHASING){
            BFL = BFL|BFL_CHASING;
			
            vector ppos = prPos(chasetarg);
            
            // Player left sim or monster target died
            if(ppos == ZERO_VECTOR){
				setState(MONSTER_STATE_IDLE);
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
					~getRF()&Monster$RF_PACIFIED && 
					// Attack LOS, hAdd() IS added
					llList2Integer(llCastRay(llGetPos()+<0,0,1+hAdd()>, prPos(chasetarg)+<0,0,.5>, [RC_REJECT_TYPES, RC_REJECT_AGENTS|RC_REJECT_PHYSICAL]), -1) == 0
				){
					
					parseDesc(chasetarg, resources, status, fx, sex, team, mf);
					
					// not attackable
					if(
						status&StatusFlags$NON_VIABLE ||
						fx&fx$UNVIABLE
					){
						return;
					}
					
					multiTimer([TIMER_ATTACK, "", atkspeed*fxCooldownMod, FALSE]);
					raiseEvent(MonsterEvt$attackStart, mkarr([chasetarg]));
					BFL = BFL|BFL_ATTACK_CD;
					anim("attack", TRUE);
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
				
				// Movement, hAdd() is not added
                vector add = <0,0,1>;
                if(llGetAgentInfo(chasetarg)&AGENT_CROUCHING)add = ZERO_VECTOR;
                
                list ray = llCastRay(llGetPos()+add, ppos+add, ([RC_REJECT_TYPES, RC_REJECT_PHYSICAL|RC_REJECT_AGENTS, RC_DATA_FLAGS, RC_GET_ROOT_KEY]));

                if(llList2Integer(ray, -1)>0){
                    if(getRF()&Monster$RF_FREEZE_AGGRO)return;
                    string desc = prDesc(llList2Key(ray, 0));
                    Status$dropAggro(chasetarg); 

					setState(MONSTER_STATE_SEEKING);
                    // dropAggro()
                    //raiseEvent(MonsterEvt$lostTarget, chasetarg);
                }else{
                    lastseen = ppos+add;
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
	
	else if(id == "INI"){
		LocalConf$ini();
	}
}


onEvt(string script, integer evt, list data){
    if(script == "got Portal" && evt == evt$SCRIPT_INIT){
        rezpos = llGetPos();
        
        LocalConf$ini();
		multiTimer(["INI", "", 5, FALSE]);	// Some times localconf fails, I don't know why
    }
    
	if(Portal$isPlayerListIfStatement)
		PLAYERS = data;
	
	// Tunnels legacy into the new command
    else if(script == "got LocalConf" && evt == LocalConfEvt$iniData){
		multiTimer(["INI"]);
		list out = [];	// Strided list
		integer i;
		for(i=0; i<count(data); i++){
			if(isset(l2s(data,i))){
				out+= [i]+llList2List(data, i, i);
			}
		}
		
		// Description should be applied first if received from localconf. 
		// Custom updates sent directly through Monster$updateSettings should be sent after initialization to prevent overwrites
		string override = portalConf$desc;
		if(isset(override)){
			list dt = llJson2List(override);
			override = "";
			list_shift_each(dt, v,
				list d = llJson2List(v);
				if(llGetListEntryType(d, 0) == TYPE_INTEGER)
					out += llList2List(d, 0, 1);
			)
		}
		
		Monster$updateSettings(out);
    }
	
    else if(((script == "ton MeshAnim" || script == "jas MaskAnim") && evt == MeshAnimEvt$frame) || (script == "got LocalConf" && evt==LocalConfEvt$emulateAttack)){
        
		list split = llParseString2List(llList2String(data,0), [";"], []);
        string task = llList2String(split, 0);
        
        if(task == FRAME_AUDIO)llPlaySound(llList2String(split,1), llList2Float(split,2));
        else if(task == Monster$atkFrame || (script == "got LocalConf" && evt == LocalConfEvt$emulateAttack)){
            list odata = llGetPrimitiveParams([PRIM_POSITION, PRIM_ROTATION]);

            list ifdata = llGetObjectDetails(chasetarg, [OBJECT_POS, OBJECT_ROT]);
            vector pos = llList2Vector(odata,0);
            vector dpos = llList2Vector(ifdata, 0);
            
            if(~getRF()&Monster$RF_NOROT && chasetarg != "" && (look_override == "" || look_override == NULL_KEY))
                llLookAt(<dpos.x, dpos.y, pos.z>, 1,1);
            
            float dist = llVecDist(pos, dpos);
            if(dist>hitbox*2)return;
            
            raiseEvent(MonsterEvt$attack, mkarr([chasetarg]));
        }
        
    }
    
    else if(script == "got Status"){
        if(evt == StatusEvt$dead){
            if(~BFL&BFL_DEAD && llList2Integer(data,0)){
                BFL = BFL|BFL_DEAD;
                toggleMove(FALSE);
				setState(MONSTER_STATE_IDLE);
				chasetarg = "";
            }
			else if(!l2i(data, 0))
				BFL = BFL&~BFL_DEAD;
        }else if(evt == StatusEvt$monster_gotTarget){
			chasetarg = llList2String(data, 0);
			
            if(BFL&(BFL_STOPON|BFL_SEEKING))return;
            if(llList2String(data, 0) != ""){    
				setState(MONSTER_STATE_CHASING);
            }
        }
    }
    
    else if(script == "jas MaskAnim" || script == "ton MeshAnim"){
        if(evt == MeshAnimEvt$agentsInRange)
            BFL = BFL|BFL_PLAYERS_NEARBY;    
        else if(evt == MeshAnimEvt$agentsLost)
            BFL = BFL&~BFL_PLAYERS_NEARBY;
    }

}

// Settings received
onSettings(list settings){ 
	integer flagsChanged;
	while(settings){
		integer idx = l2i(settings, 0);
		list dta = llList2List(settings, 1, 1);
		settings = llDeleteSubList(settings, 0, 1);
		
		// Flags
		if(idx == 0){
			RUNTIME_FLAGS = l2i(dta,0);
			flagsChanged = TRUE;
		}
		// Movement speed
		if(idx == 1 && l2f(dta,0)>0)
			speed = l2f(dta,0);
			
		// Hitbox
		if(idx == 2 && l2f(dta, 0) != HITBOX_DEFAULT)
			hitbox = l2f(dta, 0);
		
		// Attackspeed
		if(idx == 3)
			atkspeed = l2f(dta,0);
		
		if(idx == 5 && l2f(dta,0)>=0){
			wander = l2f(dta,0);
		}
        
		if(idx == MLC$height_add)
			height_add = l2i(dta,0);
		
		
	}
	
	// Limits
	if(speed<=0)
		speed = 1;
	if(hitbox<=0)
		hitbox = 3;
    
	if(flagsChanged)
		raiseEvent(MonsterEvt$runtimeFlagsChanged, (string)getRF());
	
	if(~BFL&BFL_INITIALIZED){
		BFL = BFL|BFL_INITIALIZED; 
		multiTimer([TIMER_FRAME, "", .25, TRUE]);
		raiseEvent(MonsterEvt$confIni, "");
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
	/*
    #define LISTEN_LIMIT_LINK LINK_THIS
    #define LISTEN_LIMIT_FREETEXT if(llListFindList(PLAYERS, [(string)llGetOwnerKey(id)]) == -1)return;
    #include "xobj_core/_LISTEN.lsl"
    */
	
	#define LM_PRE \
	if(nr == TASK_FX){ \
		list data = llJson2List(s); \
		FXFLAGS = l2i(data, FXCUpd$FLAGS); \
		if(RUNTIME_FLAGS & Monster$RF_IS_BOSS)FXFLAGS = FXFLAGS&~fx$F_STUNNED; \
		fxSpeed = i2f(l2f(data, FXCUpd$MOVESPEED)); \
		fxCooldownMod = i2f(l2f(data, FXCUpd$COOLDOWN)); \
		if(FXFLAGS&(fx$F_STUNNED|fx$F_ROOTED))toggleMove(FALSE); \
	} \
	else if(nr == TASK_MONSTER_SETTINGS){\
		onSettings(llJson2List(s)); \
	}\
	
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
        return;  
    }
    
    // Public
    if(METHOD == MonsterMethod$toggleFlags){
        integer pre = getRF();
		// Basic flags
		if(!l2i(PARAMS, 2)){
			RUNTIME_FLAGS = RUNTIME_FLAGS|(integer)method_arg(0);
			RUNTIME_FLAGS = RUNTIME_FLAGS&~(integer)method_arg(1);
        }
		// Spell flags
		else{
			RUNTIME_FLAGS_SPELL = RUNTIME_FLAGS_SPELL|(integer)method_arg(0);
			RUNTIME_FLAGS_SPELL = RUNTIME_FLAGS_SPELL&~(integer)method_arg(1);
		}
        
        raiseEvent(MonsterEvt$runtimeFlagsChanged, (string)getRF());
        if(getRF()&Monster$RF_IMMOBILE){
            toggleMove(FALSE);
        }  
        if(pre&Monster$RF_NOROT && getRF()&Monster$RF_NOROT){
            llStopLookAt();
        }
		
    }
	else if(METHOD == MonsterMethod$seekStop){
		BFL = BFL&~BFL_SEEKING;
		setState(MONSTER_STATE_IDLE);
	}
	else if(METHOD == MonsterMethod$seek){
		BFL = BFL|BFL_SEEKING;
		setState(MONSTER_STATE_SEEKING);
		SEEKTARG = [method_arg(0)];
		if((vector)method_arg(0))
			SEEKTARG = [(vector)method_arg(0)];
		SEEKTARG += l2f(PARAMS, 1);
		SEEKTARG += l2s(PARAMS, 2);
	}
	
    else if(METHOD == MonsterMethod$lookOverride){
		look_override = method_arg(0);
		updateLookAt();
	}
	else if(METHOD == MonsterMethod$atkspeed)atkspeed = (float)method_arg(0);
    #define LM_BOTTOM  
    #include "xobj_core/_LM.lsl"   
}
