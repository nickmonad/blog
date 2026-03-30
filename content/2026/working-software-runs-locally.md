+++
title = "Working software runs locally"
date = 2026-03-30
[taxonomies]
tags = [ "testing", "tooling" ]
[extra]
image = "/images/working-software-runs-locally.png"
+++

I've been thinking a lot about testing recently.

Although, it's kind of a "blessing and a curse" situation. A blessing in the sense that I've had the
opportunity to work on some interesting problems, with some very interesting tools. At work, we've been testing a product that
does simulation testing and as a result, I've seen some of the most powerful software I've ever seen in my professional
career. How is it a curse? Well, testing complex software is... complex. And an increased focus on testing is
usually done after a handful of stressful situations.

In any case, this recent focus on testing has reinforced my feeling that all software should be able to run locally,
on every developer's machine in the organization, all the time, with minimal friction.

Of course, the software I'm working on _can_ always run on my machine, in the sense that all computers
can (theoretically) run all software. What I mean by "run" is more practical and pertinent to testing.
I'm talking specifically about the ability to start something locally, run a few commands against it, or throw
some predefined requests at it, to see how it behaves. This also includes external dependencies, to a reasonable degree
of fidelity.

In my experience, having the ability to do this repeatedly and reliably increases my ability to understand
and confidently change the system I'm working on.

As an example of this, I recently found myself trying to debug a configuration issue in a deployed testing environment.
My initial instinct was to stay as close to the deployment as possible, in order to be certain I was making the correct
changes. After an embarrassing amount of time fumbling around with these settings, I finally remembered that I had a
script laying around that could run this component locally. Moving my efforts to my own machine made a huge difference!
I didn't have to wait nearly as long for the service to redeploy after a configuration change, and I was able to
prove the problem persisted, regardless of the runtime platform. Having this kind of tight feedback loop gave me the
confidence to dig more into the code and finally find the bug. Once I had a working hypothesis based on the code,
I could validate it within seconds.

I've come across a surprising number of situations where existing tooling in a codebase doesn't support this.
Or, you can tell that it did at some point, but the specification for it has rotted to the point of being useless.
At best, the service can be compiled and maybe a handful of integration tests can run. I can probably even deploy it!
But, I can't run it in a mock environment locally. [^1]

It's interesting to me how this happens, because I don't think most systems start out this way. Running things
locally is a critical part of the early development cycle. I think that over time as more external dependencies are
added, and especially as the CI/CD pipeline matures, the ability to run a complex system locally moves further out of
reach, mostly without even realizing it.

One reason I think this tends to happen is pressure to move quickly. If a team is under the gun to ship fast and
there is infrastructure in place to do some quick validation in the deployed environment, it's easy to forget about
the local experience.

Perhaps though, there's a sense that the local experience doesn't actually matter all that much, because true
validation comes from production deployment. Charity Majors argues the point about validation in her (now famous?)
article ["I test in prod"](https://increment.com/testing/i-test-in-production/).
I don't think she's arguing against running things locally (the word "local" isn't even in the article),
but if the idea we should test in prod is taken to a sort of extreme, I can see how it would be easy to come to the
conclusion that production is the only thing that matters, at the cost of other means of validation.
I would argue that both matter: the ability to test locally, _and_ test in production. [^2]

Another reason I think local tooling degrades is the perception that it's not actually possible to bring up the system
locally, in a way that a simulated "end-to-end" request could be satisfied. For the most part, I haven't ever found
this to be true. There are tons of tools that make these setups possible: public docker images, docker compose, LocalStack,
or straight up writing a custom fake or mock. All are viable options. [^3]

My general perspective is that if a tool to mock/simulate an external dependency doesn't already exist and is
accessible, it's at least worth considering building your own. This can even just be a handful of endpoints your
specific system actually needs. Recently, I needed to mock an internal API layer so I could satisfy the system
I was actually concerned about testing. All I needed to mock was 5 or 6 endpoints, from a system that actually has
dozens. Finding a minimal footprint and starting there can go a long way. In this case, the mock was just a Python
server passing some JSON back and forth, with a little bit of internal state.

Developing a habit and practice of this sets up for a lot of really interesting testing techniques way beyond
manual validation. Simulation testing is one of those techniques, and it feels like a super power once you
get the hang of it. Pierre Zemb goes into more detail on this in ["Why Fakes Beat Mocks and Testcontainers"](https://pierrezemb.fr/posts/why-fakes-beat-mocks-and-testcontainers/).[^4]

At some point though, faking/mocking _can_ get out of control. I understand the desire to not feel like we're maintaining a
whole other system, with all of its complications and quirks. If that starts to happen, it might be worth thinking
about how to bring in that other system you're mocking, and run it alongside your system. I think this is actually the preferred option. Especially
if that other system's external dependencies could be mocked with a smaller footprint.

In the worst case, build what you can. It's OK to scope something down. A little bit goes a long way here and
there's always some creativity involved. We make the perfect the enemy of the good far too often.

I want to be careful in setting the expectation here. I don't think I should be able to run a system _at scale_
on my laptop. I'm not going to run Google's primary search infrastructure and recreate a production environment
that serves billions of users. But, I do hope I would be able to at least run a minimally working version of it
(or some critical component of it), in a way that approximates useful results. If I change some aspect of the code,
I should be able to see the impact of that change.

Just like we consider failing unit tests to be a blocker for getting to production, I think we need to start
considering a broken local setup to be a blocker. Certainly not in the absolute sense. If you need to ship a
fix to production _right now_, please, do it. But, take the time to come back and tidy up. Under normal working
conditions, we should not neglect the workspace right in front of us.

-------

[^1]: I have also come across situations where even compiling locally is too much to ask. At some point, the
standard advice becomes "just push it to CI". This is probably the worst situation to be in.

[^2]: I agree with a lot of the conclusions in that article. And, at the time of this writing, Charity's article is nearly 7 years old. Since then, there has been a lot of
development in deterministic simulation testing (DST), which _can_ actually bring the chaos of a production environment
to an environment where there's truly no risk. (See [Antithesis](https://antithesis.com/))
Also, DST tends to be far more aggressive than any real production environment.
I still think her fundamental conclusions are sound, but new tooling improves the pre-prod testing story significantly. Ensuring a system has strong and stable
tooling for local testing actually sets it up nicely for simulation testing, which is a big reason why I'm advocating for it here.

[^3]: Yes, I am aware that LocalStack has done some weird things recently, with regards to access and pricing.
I don't quite know what to make of it, but I remain hopeful that good tooling continues to be developed and is accessible to the broadest possible audience.

[^4]: Pierre specifically uses the term "fake" instead of "mock" to describe this technique. I think I would prefer the term
"simulated", since it's so useful in the context of simulation, but "fake" works as well. The term mock might have
some baggage associated with it, depending on who you're talking to. Whatever the term is for what I'm describing here,
the main thing is to be on the same page with your colleagues.
