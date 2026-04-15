package game

DiceUpgrade_Antenna :: struct {}
DiceUpgrade_Journalist :: struct {}

DiceUpgrade :: union{
	DiceUpgrade_Antenna,
	DiceUpgrade_Journalist,
}
