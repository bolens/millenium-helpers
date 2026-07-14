package suggest

// Closest mirrors scripts/lib/dispatcher.sh suggest_command scoring:
// 4=prefix, 3=substring, else shared leading chars; subsequence scores 3−|len gap| (floor 2).
// Returns "" when best_score < 2.
func Closest(input string, cmds []string) string {
	if input == "" {
		return ""
	}
	best := ""
	bestScore := 0
	for _, c := range cmds {
		score := scoreCandidate(input, c)
		if score > bestScore {
			bestScore = score
			best = c
		}
	}
	if bestScore >= 2 {
		return best
	}
	return ""
}

func scoreCandidate(input, c string) int {
	if c == input {
		return 100
	}
	score := 0
	if hasPrefix(c, input) || hasPrefix(input, c) {
		score = 4
	} else if contains(c, input) || contains(input, c) {
		score = 3
	} else {
		i := 0
		for i < len(c) && i < len(input) && c[i] == input[i] {
			i++
		}
		score = i
		if len(input) >= 2 {
			ni, hi := 0, 0
			for ni < len(input) && hi < len(c) {
				if input[ni] == c[hi] {
					ni++
				}
				hi++
			}
			if ni == len(input) {
				lenDiff := len(c) - len(input)
				if lenDiff < 0 {
					lenDiff = -lenDiff
				}
				subScore := 3 - lenDiff
				if subScore < 2 {
					subScore = 2
				}
				if subScore > score {
					score = subScore
				}
			}
		}
	}
	return score
}

func hasPrefix(s, prefix string) bool {
	return len(s) >= len(prefix) && s[:len(prefix)] == prefix
}

func contains(s, sub string) bool {
	if sub == "" {
		return true
	}
	for i := 0; i+len(sub) <= len(s); i++ {
		if s[i:i+len(sub)] == sub {
			return true
		}
	}
	return false
}
