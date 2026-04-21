package game

CardUpgrade_Antenna :: struct {}
CardUpgrade_Journalist :: struct {}

Cards :: union{
	CardUpgrade_Antenna,
	CardUpgrade_Journalist,
}

CombinationType :: enum {
	Pair,
	DoublePair,
	RollOfThree,
	RollOfFour,
	RollRoyal,
	FullHouse,
	LowerStraight,
	UpperStraight,
	AllTogether,
	OnlyOnes,
	OnlyTwos,
	OnlyThrees,
	OnlyFours,
	OnlyFives,
	OnlySixes,
}
Combination :: struct {
	type: CombinationType,
	score: i32,
	n_cards: i32,
}

test_combination :: proc(combination: CombinationType, dices: [5]i32, highlight: ^[5]bool) -> (match:bool=false, score:f64=0) {

	counter := [6]i32{}
	for number, i in dices {
		if number < 1 || number > 6 do return // Invalid dice number, return no match
		counter[number-1] += 1
	}

	pair, double_pair, three, four, five := false, false, false, false, false
	for count in counter {
		if count >= 2 {
			if pair do double_pair = true
			pair = true
		}
		if count >= 3 do three = true
		if count >= 4 do four = true
		if count >= 5 do five = true
	}
	full_house := double_pair && three
	lower_straight := counter == [6]i32{1, 1, 1, 1, 1, 0}
	upper_straight := counter == [6]i32{0, 1, 1, 1, 1, 1}

	#partial switch combination {
	case .Pair:
		match = pair
		if !match do return
		score = 15 // fixed score
		n_highlighted := 0 // Highlight only two dices
		#reverse for count, i in counter { // Always take the highest pair
			if count < 2 do continue

			for number, j in dices {
				if number == i32(i) + 1 {
					highlight[j] = true
					n_highlighted += 1
					if n_highlighted > 1 do return
				}
			}
		}

	case .DoublePair:
		match = double_pair
		if !match do return
		score = 20 // fixed score
		for c, i in counter {
			if c < 2 do continue
			n_highlighted := 0 // Highlight only four dices

			for number, j in dices {
				if number == i32(i) + 1 {
					highlight[j] = true
					n_highlighted += 1
					if n_highlighted > 1 do break
				}
			}
			if count(highlight[:], true) >= 4 do break
		}

	case .RollOfThree:
		match = three
		if !match do return
		score = 25 // fixed score
		n_highlighted := 0 // Highlight only three dices
		for count, i in counter {
			if count < 3 do continue
			for number, j in dices {
				if number == i32(i) + 1 {
					highlight[j] = true
					n_highlighted += 1
					if n_highlighted > 2 do return
				}
			}
		}
	case .RollOfFour:
		match = four
		if !match do return
		score = 40 // fixed score
		n_highlighted := 0 // Highlight only four dices
		for count, i in counter {
			if count < 4 do continue
			for number, j in dices {
				if number == i32(i) + 1 {
					highlight[j] = true
					n_highlighted += 1
					if n_highlighted > 3 do return
				}
			}
		}
	case .RollRoyal:
		match = five
		if !match do return
		score = 60 // fixed score
		for number, j in dices {
			highlight[j] = true
		}
	case .FullHouse:
		match = full_house
		if !match do return
		score = 40 // fixed score
		for number, j in dices {
			highlight[j] = true
		}
	case .LowerStraight:
		match = lower_straight
		if !match do return
		score = 50 // fixed score
		for number, j in dices {
			if number >= 1 && number <= 5 {
				highlight[j] = true
			}
		}
	case .UpperStraight:
		match = upper_straight
		if !match do return
		score = 50 // fixed score
		for number, j in dices {
			if number >= 2 && number <= 6 {
				highlight[j] = true
			}
		}
	}

	return
}
