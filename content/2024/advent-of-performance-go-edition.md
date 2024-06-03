+++
title = "Advent of Performance: Go Edition"
description = ""
date = 2024-06-03
[taxonomies]
tags = [ "golang", "performance" ]
+++

Every so often I like to spend some time working on [Advent of Code](https://adventofcode.com/) problems when I need
a break from my primary projects. It's also a great way to learn a new language, or sharpen skills in one I already know.

Another fun angle is to spend time making solutions fast. Usually, they are "fast enough" for the purposes of solving
the problem and moving on, just to get the gist of how to think algorithmically. But, in some cases, there is an obvious
slow down when going from part 1 to part 2 of a problem statement, which usually means there's a faster alternative.
[Day 4](https://adventofcode.com/2015/day/4) from the 2015 problem set provided exactly that opportunity.

## Mining AdventCoin

The problem statement for this day is essentially a simplified example of how [bitcoin mining](https://en.bitcoin.it/wiki/Mining)
works, by finding a hash collision. Given some input string (e.g. `yzbqklnj`), the goal is to find some "nonce" integer,
that when appended to the input string and hashed (using MD5), the resulting hash will have some number of leading zeros.

For example,

> If your secret key is `abcdef`, the answer is `609043`, because the MD5 hash of `abcdef609043` starts with five zeroes (`000001dbbfa...`), and it is the lowest such number to do so.

Hashes can't be "reversed", meaning that the only way to do this is to try a bunch of nonces until we find a hash
with the required number of leading zeros.

Fortunately, Go's standard `crypto` package gives us a function to compute an MD5 hash of a byte array, so we can do this
pretty simply.

```go
func naive(input []byte, prefix string) string {
	seed := strings.TrimSpace(string(input))
	nonce := 1

	for {
		preimage := []byte(fmt.Sprintf("%s%d", seed, nonce))
		hash := md5.Sum(preimage)

		if check(hash, prefix) {
			break // found nonce
		}

		nonce += 1
	}

	return fmt.Sprintf("%d", nonce)
}
```

The `check` function just formats the resulting hash in hex and looks at the prefix. We've separated it out so we can
change it later...

```go
func check(hash [16]byte, prefix string) bool {
	hex := fmt.Sprintf("%x", hash)
	return strings.HasPrefix(hex, prefix)
}
```

Easy enough! We've solved Part 1. For part 2, we just have to run the same loop, but instead of looking
for a hash with 5 leading zeros, we have to find one with 6 leading zeros.

Updating our input and running it again... Oh. Well. It definitely takes longer. Noticeably longer. In these situations,
you always wonder if something else went wrong and you've introduced an infinite loop. In this case, we definitely get correct output,
but it's just slow.

```sh
$ go build -o day4 solutions/day4/main.go

# find hash with 5 leading zeros (00000)
$ ./day4 -part 1 input/day4
282749
time: 134.816113ms

# find hash with 6 leading zeros (000000)
$ ./day4 -part 2 input/day4
9962624
time: 4.029076709s
```

Technically, nothing is "wrong" with our algorithm here. It's just dealing with a much larger space of possibilities.
Generally speaking, the more specific your target hash is, the longer it's going to take, effectively trying random
nonce values until you find the needle in a ridiculously large haystack.

Of course, Go is known for making concurrency relatively easy, so let's just spin up a goroutine for each CPU core
and try as many different nonces as we can simultaneously.

Originally, I had thought I would have `runtime.NumCPU()` goroutines as "workers" crunching on our hash function, with
_another_ goroutine that would act as a "ticket counter", giving out the next nonce over a channel when a worker needed
a new one after failing to find the desired hash prefix.

Although, it didn't actually work. At least not in the way I expected. We got the right number, but it took _even longer_ than
the naive solution when looking for 6 leading zeros.

I figured that the overhead of the coordination between all the goroutines was just too much to be worth the
parallel effort. The hashing function is so quick that it was likely the workers were putting too much contention
on the nonce channel, too quickly, causing a lot of runtime context switching and blocking.

## Actually making it fast

I knew that parallelization was definitely the way to go here because each hashing function is completely independent of the
other. No state needs to be carried over between testing nonce `32535` and nonce `871279`. Ultimately, _that_ was the key insight
needed to make this work.

If we consider each worker in isolation, we can define a simple formula for determining the next nonce in its sequence to test.
Just make it count upwards, skipping by some fixed amount each iteration. In this case, the number of goroutines. This way, each worker
tests a unique sequence of integers, but doesn't overlap with any other worker.

For simplicity, let's assume we have 4 workers. If they each count by 4, starting from a different place, they'll never overlap.

```
worker 0 -> 0, 4, 8, 12, ...
worker 1 -> 1, 5, 9, 13, ...
worker 2 -> 2, 6, 10, 14, ...
worker 3 -> 3, 7, 11, 15, ...
```

Each worker can calculate this sequence with 2 constants, the "base" (starting point), and "N", the number of workers.

```
nonce = base + (i * N)
```

If `i` increases indefinitely until we either find a solution, or are told to stop looking, we can parallelize this
and eliminate virtually all coordination between each worker, until it needs to notify us of a solution.

```go
func optimized(input []byte, prefix string) string {
	seed := strings.TrimSpace(string(input))
	numWorkers := runtime.NumCPU()

    // wait group ensures all goroutines clean up after cancellation
	var wg sync.WaitGroup

    // cancellable context is cancelled once a solution is found
	ctx, cancel := context.WithCancel(context.Background())

    // given to each worker
	solution := make(chan int, 1)

    // spawn a worker for each CPU core
	for b := 0; b < numWorkers; b++ {
		wg.Add(1)
		go func(base, n int) {
			defer wg.Done()

			i := 0
			for {
				select {
				case <-ctx.Done():
					return

				default:
					nonce := base + (i * n) // independently calculate next nonce in sequence
					preimage := []byte(fmt.Sprintf("%s%d", seed, nonce))
					hash := md5.Sum(preimage)

					if check(hash, prefix) {
						solution <- nonce
						return
					}

					i = i + 1
				}
			}
		}(b, numWorkers)
	}

	winner := <-solution
	cancel()

	wg.Wait()
	return fmt.Sprintf("%d", winner)
}
```

And the result...

```sh
$ ./day4 -part 2 input/day4
9962624
time: 3.976446064s

$ ./day4 -part 2 -optimized input/day4
9962624
time: 699.66703ms
```

Boom. Huge difference!

This solution actually helps improve performance in part 1 as well.

```sh
$ ./day4 -part 1 input/day4
282749
time: 119.919216ms

$ ./day4 -part 1 -optimized input/day4
282749
time: 22.183944ms
```

## One more thing!

Remember the `check` function above? It encodes the resulting MD5 hash into hexadecimal and looks at that string
to see if the nonce results in a hash with the desired number of leading zeros.

Primarily leaning on `fmt.Sprintf()` and the hex formatting directive, it requires allocating heap memory to build the hex string, which must be done
on every iteration of the loop.

Since all we really need to do is check the leading byte values of the hash, we can perform that check
without any heap allocation at all.

```go
// Check if the given MD5 hash has the given leading number of zeros.
func check(hash [16]byte, leading int) bool {
	numBytes := leading / 2
	for i := 0; i < numBytes; i++ {
		if hash[i] != 0x00 {
			return false
		}
	}

	if leading%2 != 0 {
		// looking for odd number of zeros...
		// since each hex character represents 4 bits, we have to use a bit shift to check our last byte
		// in the hash if the desired number of leading zeros is odd. For example, if we are looking for
		// `000` (odd number of zeros), the byte sequence _could_ be `0x00 0x01`, or `0x00 0x02`, etc...
		// In this case, we bit shift the last byte to the right by 4, and check if that result is 0,
		// ignoring 4 least significant bits.

		// last index in hash to check is equal to `numBytes` because of the integer division above.
		// for example, if leading == 5, numBytes == 2 (due to integer division), and we need to
		// check the 3rd byte in the sequence (i.e. index 2)
		return (hash[numBytes] >> 4) == 0x00
	}

	return true
}
```

Because a single digit of a hex value actually represents 4 bits, looking for 6 leading zeros in the resulting hash
means we look at the first 3 bytes. (`0x000000` split on each byte looks like `0x00 0x00 0x00`.)

If we need to check for an odd number of leading zeros (say, 5 like in part 1), we can lean on some integer division
and a modulo check to ensure we check the last byte in the sequence correctly. As we said, that last 0 to check only
represents 4 bits, so we can use a bit shift to ignore the 4 least significant bits of the byte, and check that result
against the `0x00` byte value.

Assuming we get through those checks, we've found a solution!

Looking at the run time, this updated version of `check` improves performance across the board, in both
the naive solution, and optimized solution that uses parallelization!

```sh
$ ./day4 -part 1 input/day4
282749
time: 55.216603ms

$ ./day4 -part 2 input/day4
9962624
time: 1.818860088s
```

```sh
$ ./day4 -part 1 -optimized input/day4
282749
time: 11.829511ms

$ ./day4 -part 2 -optimized input/day4
9962624
time: 319.841772ms
```

## Summary

Here's a table summarizing the performance improvements for both part 1 and part 2. In each case, I ran the
solutions 10 times and took the average of those reported run times, rounded to 2 decimal places.

("no alloc" means the version of `check` that doesn't allocate a string and encode to hex)

|Solution|Version|Run Time|Speedup|
|-|-|-|-|
|Part 1|`naive`|`118.16 ms`|`1.0x`|
||`naive + no alloc`|`53.2 ms`|`2.2x`|
||`optimized`|`20.04 ms`|`5.9x`|
||`optimized + no alloc`|`10.2 ms`|`11.6x`|
|Part 2|`naive`|`4.01 s`|`1.0x`|
||`naive + no alloc`|`1.81 s`|`2.2x`|
||`optimized`|`778.41 ms`|`5.2x`|
||`optimized + no alloc`|`358.53 ms`|`11.2x`|

#### Environment

I ran these tests using Go version `go1.22.3 linux/amd64`, on a ThinkPad X1 Extreme Gen 4i, rocking an
11th Gen Intel i7-11800H (16) @ 4.600GHz (reported by `neofetch`)

All code for this and other solutions can be found on [GitHub](https://github.com/nickmonad/advent-of-code/)
