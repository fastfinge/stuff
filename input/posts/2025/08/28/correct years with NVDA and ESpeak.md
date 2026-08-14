Title: Correcting Years With NVDA and Espeak
Published: 2025-08-28
Tags:
- articles
Lead: If the title of this one doesn't interest you, the contents sure won't!
Fedi: https://fed.interfree.ca/notes/abzr1adzzq4m91hj
---
I'm mostly documenting this for myself.  I've been trying to switch away from eloquence for ages, with little success. One possibility is [Espeak-ng](https://github.com/espeak-ng/espeak-ng), at least with [NVDA](https://www.nvaccess.org) on Windows, and on Android. Unfortunately, Espeak on IOS has a bunch of serious bugs, and hasn't been updated in forever.

One problem with Espeak, though, is that I loathe the way it reads years.  It doesn't do any date processing, and nor should it; I don't want to use a January second cup of flour. But I also don't want 1987 read out as "nineteen hundred eighty seven". In order to fix this, add a dictionary entry in NVDA as follows:
* pattern: \b([1-9][0-9])([1-9]{2})\b
* replacement: \1 \2
* case sensitive: checked
* type: regular expression

This will match on any four digit number that doesn't start with a zero, and where digits three and four are not zeros, and add a space between digits two and three. So "19 87" but not "20 01" or "19 00". 

In other news, the pattern I wrote for this years ago was apparently back when I didn't know about \b being the word boundary. It did horrible things like ending with (?:(?!\d)+) to make sure it only modified four digit numbers. I found it while doing something else with NVDA dictionaries, and cleaned it up in horror.