+++
title = "nostr NIP-05 DNS Verification for a Zola-based Static Site"
date = 2023-02-05
draft = true
+++

<i>Skip down to the `NIP-05 & Zola` section if you already know about nostr and want to get right into the technical
specifics about nostr DNS verification with zola.</i>

For the past few weeks, I've been doing some research on [nostr](https://github.com/nostr-protocol/nostr),
a new approach for decentralized social-networking.

What I appreciate about nostr is how radically simple the protocol really is. Anybody who is reasonably technical can
understand the protocol at a high-level in just a few minutes, and it's fun to think about all the challenges
and possibilities that will arise as it scales to millions of users.

I love how straightforward and to-the-point this answer is from the protocol FAQ, which I think is really getting at
where all the hype is coming from.

> <i>This is very simple. Why hasn't anyone done it before?</i>
>
> I don't know, but I imagine it has to do with the fact that people making social networks are either companies
> wanting to make money or P2P activists who want to make a thing completely without servers.
> They both fail to see the specific mix of both worlds that Nostr uses.

Sometimes the best solutions are a blend of various approaches that, on their own, were optimized too far in one
direction or another, as noted in the answer above. Nostr takes a different approach. It uses well-defined and
standardized technology that has been around for quite some time, but never put together in this specific way. I think
a lot of people see that same magic in bitcoin as well. It was developed using technology that already existed, just
never put together in that way before.

I'll save the more philosophical rambling about nostr for another time. Now that I've finally setup a key-pair and
started posting to relays, I wanted to make a quick post about how I setup DNS verification of my public key using
[`zola`](https://getzola.org), the static site generator this blog is rendered with.

### NIP-05

The nostr protocol development process has the notion of a "NIP", or a "Nostr Implementation Possibility", in a similar
vein to bitcoin's [BIPs](https://bips.dev) ("Bitcoin Improvement Proposals"). These are ways the community can propose
new ideas or extentions to the base nostr protocol. Some may be mandatory, but most are optional, and can be specified
for relays, clients, or both.

[NIP-05](https://github.com/nostr-protocol/nips/blob/master/05.md) describes how clients can use DNS and a simple
HTTP `GET` request to add an extra mapping for a user on nostr. This can give some extra assurance to a follower
that who they are following is legitimate, or mark them as part of an organization (maybe a company or development group).

Basically, a user can sign a nostr event published to relays that sets metadata about their "account"
(technically, their public key). One of those fields that may be set is a `nip05` field, containing a `name@domain.com`
value. Clients can make a request to `https://domain.com/.well-known/nostr.json?name=name` and if the public key returned
matches the public key of the signed metadata event, that "account" is a considered verified against that domain.

To be fair, if that domain is ever compromised in some way, the key mapping could also be compromised, misleading
followers. But, it's a reasonable level of assurance, considering we're operating in a decentralized context.

### NIP-05 & Zola

Since I happen to own a custom domain, and I use [`zola`](https://getzola.org) to render my content as a static site, I
wanted to figure out a way to add `NIP-05` verification to my nostr profile.

Fortunately, `zola` can do this pretty easily, but the setup is not immediately obvious. We know that for page content,
we should have markdown files and folders under our `content/` directory, and that these map to URL paths during the
build process.

Following the `NIP-05` specification, we need to have a path like `/.well-known/nostr.json` for our domain we want
to verify against. If we create that file at `content/.well-known/nostr.json`, build our site and try to navigate there,
we actually get a `404` response.

This is because zola won't build any directory or include files in the final path structure if there isn't a `_index.md`
present in that directory. To get around this, we can create one at `content/.well-known/_index.md` that looks like,

```
+++
title = "nostr.json"
render = false
+++
```

Looking at the section configuration options [here](https://www.getzola.org/documentation/content/section/#front-matter)
we can see that the `render` option is used to prevent any actual template from being rendered into the final path,
but still leaves `/.well-known/nostr.json` available to request.

Once `_index.md` and `nostr.json` are present under `content/.well-known/`, we're ready to build, re-publish our site,
and set our `nip05` identifier in a nostr client that supports it. (I used [iris.to](https://iris.to))

If you want to see the final result for this site, checkout
[nickmonad.blog/.well-known/nostr.json](https://nickmonad.blog/.well-known/nostr.json)

#### Quick things to note.

* If you are not using your own server to host your zola static site, your hosting provider must support setting
custom header responses for specific paths. In this case, I had to ensure I was setting `Access-Control-Allow-Origin: *`
as a response header to all `/.well-known/*` requests, so Javascript web clients can make that request.
* If you want to just verify your top-level domain, you need to set `"_"` as the "name" in your `nostr.json`. See the
link above for this site as an example.
