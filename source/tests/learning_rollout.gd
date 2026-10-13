extends "res://tests/ai_match_review.gd"
var learn_team:int=0
var policy_path:String=""
var opponent_path:String=""
var train:bool=false
var previous_score:Array=[0,0]
var wrote:bool=false
func begin()->void:
	super.begin()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--learn-team="):learn_team=int(arg.trim_prefix("--learn-team="))
		if arg.begins_with("--policy="):policy_path=arg.trim_prefix("--policy=")
		if arg.begins_with("--opponent="):opponent_path=arg.trim_prefix("--opponent=")
		if arg=="--train-policy":train=true
	var policy=game.tactical_director.learned_policy
	policy.models.clear();policy.enabled=false
	policy.training=train;policy.rng.seed=seed_value+87461
	if not policy.load_model(learn_team,policy_path):push_error("Policy validation failed");quit(3);return
	if not opponent_path.is_empty() and not policy.load_model(1-learn_team,opponent_path):push_error("Opponent policy validation failed");quit(3);return

func observe(dt:float)->void:
	if finished:return
	var policy=game.tactical_director.learned_policy
	var score:Array=game.services.rules.scores
	for team in [0,1]:
		var goals:int=int(score[team])-int(previous_score[team])
		if goals!=0:
			policy.credit(team,20.0*goals);policy.credit(1-team,-20.0*goals)
	previous_score=score.duplicate()
	var terminal:bool=game.services.rules.state_name()=="FULL_TIME" or game.get_meta("drill_terminal",false)
	if not wrote and (elapsed+dt>=duration or (full_match and terminal)):
		wrote=true;policy.finish(terminal)
		var result:Dictionary={"schema":"football_team_ppo_rollout_v1","seed":seed_value,"learner_team":learn_team,"train":train,"scores":score,"terminal":terminal,"duration":elapsed+dt,"traces":policy.traces,"decision_counts":policy.decision_counts,"policy":policy_path,"opponent":opponent_path,"all_ai":setup_ok,"actors":game.players.size()}
		FileAccess.open(output+".learning.json",FileAccess.WRITE).store_string(JSON.stringify(result))
	super.observe(dt)
