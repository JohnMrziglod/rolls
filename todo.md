- allow to replace old face upgrades with new one
- 

# dice cards
- !hedge fund!: This die adds the sum of all your other dice to its own score. Sets the other dice' scores to 0.
- spikes: This die applies -1 HEALTH for all antagonist's dice that it touches
- copy cat: copies the abilities from the upgrade on its left
- vodooist: This die creates a ghost joker die when it dies.
- mirror: Retriggers the abilities from the upgrade on its left.
- average joe: This die scores the average of all dice extra.
- dancer: when there are dice showing 5 and 6, this die scores +15.
- driver: This die multiplies its score if it last pips were lower than the current ones.
- (unique) birthday kid: duplicates one of your hand cards
- (unique) introvert: multiplies its own points by empty upgrade slots on the same die
- (unique) genius: creates a cycle card

# flash cards (yellow)
- bonus points: get some score points once, also with x2 factor
- upgrade dice cards: some dice upgrades reach next level
- upgrade combinations: all combinations that contain a pair, get +5 Score
- challenge: if you fullfill this challenge, you'll get bonus points + cards
- ghost refill: fill all ghost spots with random ghost dice
- create two random roll cards
- create two random dice cards
- create two random flash cards
- duplicate a random hand card
- recreate your last used tactic card
- mechanic: if in hand, you can reclaim a dice card from an upgraded die
- 

# antagonists
- Each antagonists has a special army of dice and some starting roll cards with a high lifetime

## in progress
- The MOGUL: journalists, influencers
- The CEO: investors, !HEDGE FUND!
- The Aggressor: assassins + full attack
- The Chaos: anarchists + suidice, market crash
- The Tycoon: trains, engineers
- The Scientist: librarians, historians, researchers, !genius!
- The Spiritual: mediums + ghost hour, doppel geist
- The PARTY: optimists, !birthday kid! + happy hour
- The Calm: average joes, !introvert!
- The Outlaw: pirates + tomb raider

## done
- The NOOB: Is the first opponent, has nothing and gives tutorial. 
  You encounter him later again. He is obsessed with you, he improved. 
  In the final stage, he is driven by madness and became... like you (nickname: Mirror? Fanatic? Stalker?)
- The Dictator: tanks, generals, !VIP! + fake news
- The Mathematician: power ups, plus ones

daskennstdudochschonpassmalauf


# Structure

## States
Menu
  Main
  Settings
  Credits
Game
  SaveAndExit,
	AntagonistWelcome,
	
	WaitForRoll,
	Charging,
	PreRolling,
	Rolling,
	
	DiceUpgrades,
	CardsBattle,
	DicesBattle,
	DiceDeaths,
	DiceScoring,
	CardsScoring,
	ScoringSummary,
	
	WaitForAI,
	
	GhostBoard,
	CardsOffer,
	UpgradeDie,
	
	Victory,
	Defeat,
