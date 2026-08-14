Title: My Accessible Self-hosting Tech Stack
Lead: The current apps I self-host and how they're working for me.
Published: 2025-04-10
Image: img/5302475.png
Tags:
- articles
Fedi: https://fed.interfree.ca/notes/a6f9an4mad53ffxy
---
I've been hosting services for myself and others for over 25 years now: starting on IIS6, moving to Windows Server, eventually to Debian, and now to an entirely dockerized stack.  Self-hosting allows me to control my destiny in a way that using cloud services run by others doesn't.  If an update causes screenreader issues, I can just not apply it. If I don't like the default themes, I can change them. In most cases, the projects I host are open-source, meaning I can contribute fixes myself, or write plugins to meet my specific accessibility needs.  In this article, I'll go over the tech choices I've currently made, why I made those choices, and how they're working out for me.  As it can be disappointing to set up and configure an app for hosting, only to find out it doesn't work with your screenreader, I thought it would be a good idea to document what I'm currently using.  If you're interested in taking the same control yourself, or just curious about the accessibility of the self-hosting landscape, I hope you'll find this post useful and informative.  

Note:  where I mention paid services, I have no relationship with those companies and organizations beyond being a customer.  I intentionally did not include referral codes, and I receive no compensation for discussing them.  

### DNS, email, and Domains ###

I've been a satisfied customer of [EasyDNS](https://easydns.com) for all of my DNS and domain hosting needs since 2004.  Their legacy control panels have always been fully accessible, and when they rolled out the new beta of the DNS editor, it was completely accessible from the get-go.  I've also used their email hosting for several projects, and had excellent delivery rates, with well-supported and documented imap and smtp settings that have always worked with the email clients of my choice.  The few times I've needed to interact with support they've been friendly, quick, and helpful.  Plus, they're a Canadian company with offices in Toronto that's been around since 1998.  What's not to love?  

### VPS Hosting ###

I've always avoided the major clouds as hosting providers; I want my data hosted in Canada, and I want to support small businesses. This has meant I've moved servers many times over the years, as companies come and go.  While it's a bit of effort, at least it means I know my backup and migration strategies work well!  My current pick for server hosting is [ServaRica](https://servarica.com).  The website is largely accessible, the prices are reasonable, support is quick, and the data center is in Montreal.  They also offer specialized VPS plans for applications that require large amounts of storage, meaning I don't have to purchase storage from S3.  

### Management and Orchestration ###

The solution I'm currently happiest with for managing everything is [Cosmos Cloud](https://cosmos-cloud.io).  Perfectly suited for individuals and small organizations, it gives you a reverse proxy, VPN, single sign on provider, backups, a firewall, and web-based docker management and monitoring out of the box.  Best of all, it uses standard tools behind the scenes.  If it doesn't offer a feature or app I need, or part of the web interface has accessibility issues, I can fall back to the command line, and everything will remain just as integrated as if I'd used Cosmos Cloud's management interface.  That's not only an accessibility win, it also means that I'm not locked into Cosmos Cloud if I'd ever like to change things down the road.  

### File Storage and Sync ###

In order to get files where they need to be, and keep the things that need keeping, I currently use a combination of [rClone](https://rclone.org) and [Kubo](https://github.com/ipfs/kubo).  My eventual hopes and dreams are to move everything over to NFS and ZFS, but that's going to be a good deal of planning and work that I just haven't gotten around to mapping out yet.  In the meantime, rClone works well for moving large files like backups around, and Kubo makes for a decent combination of storage provider and CDN.  

### My Home on The Fediverse ###

There is a massive community of people with disabilities, accessibility practitioners, and fellow leftists on Mastodon and other Activity pub compatible services.  In order to interact with them, I host my identity (@fastfinge@interfree.ca) using [Iceshrimp.NET](https://iceshrimp.dev/iceshrimp/iceshrimp.net).  While the accessibility of the built-in interface isn't yet perfect, Iceshrimp.NET uses an API first model of development.  That means it's fully compatible with all of my favourite apps (Enafore in my case), and even has swagger built-in to help me understand and interact with any Iceshrimp.NET specific endpoints.  As a bonus, it's even written in C#, a language I enjoy working with.  Unless you depend on Tweesecake or TWBlue, two apps that only support standard Mastodon, I strongly encourage giving iceshrimp.NET a look if you'd like to host your own fediverse server.  

### Forums ###

Of course, I also host the servers for [RBlind](https://www.rblind.com), a [Lemmy](https://join-lemmy.org) instance.  In general, the developers are responsive to accessibility feedback, and updates and maintenance are quick and easy.  However, Lemmy is by far the service I host that takes the largest amount of resource, both in disc space and ram.  As well, deploying Lemmy yourself without following the developer provided templates can be a bit fiddly; different URLs need to go to different services, based not just on the hostname or path of the URL, but also on the HTTP headers provided by the client.  It's also important to know that the Lemmy developers are tanky style communists, with a track record of genocide denial, revisionist history, and censorship.  But that doesn't affect the overall code quality or the ability to file bugs and pull requests.  It's possible to run the software without supporting the views of the creators.  In my opinion, that's the entire point of open-source selfhosting.  

### Chat ###

In an excess of optimism, I run the [Ergo](https://ergo.chat/about) IRC server, as it's the server that supports the largest number of the [IRCV3](https://ircv3.net/software/servers) features.  However, as most projects don't use IRC anymore, I also run the [Conduwuit](https://github.com/girlbossceo/conduwuit) matrix homeserver.  While Ergo was easy to set up and never breaks, getting Conduwuit to even run took me hours and hours. Conduwuit still restarts once an hour or so, sometimes randomly loses my encryption keys, and I have absolutely no idea why.  I pride myself on keeping up with modern technology...but IRC is one of my "old man yells at cloud" moments.  It's simple, it's easy, and it just works!  Why does everyone want Matrix, again?  IRC was good enough for us in 1995, and it remains good enough for us today!  

### Notes ###

For secure storage and sharing of notes, I'm using [Joplin](https://github.com/laurent22/joplin/blob/dev/packages/server/README.md).  All of the cross-platform clients are accessible, the server is easy to set up, and the encryption offers security without getting in the way.  

### RSS ###

My RSS reader of choice is [Miniflux](https://miniflux.app).  It works with all of the major RSS readers, as well as having a minimalist and accessible web interface that's a delight to use.  It's a single, self-contained binary that's quick and doesn't require many resources other than a small PostgreSQL database.  

### URL Shortening ###

While URL shorteners aren't ideal, either from a security or preservation perspective, they're still sometimes needed. The increased character limit of Mastodon and other social networks has obviated the need for them online, but they're still useful in person.  If I'm giving a URL out over the phone, posting it on a sign or poster, or mentioning it during a presentation, I like to have a custom and easy to remember web address.  I use [Lynx](https://github.com/Lynx-Shortener/Lynx) for this purpose, largely because it doesn't come with much built-in tracking.  I neither need or want to know the country, browser, operating system, and underwear size of anyone who uses one of my shortened URLs.  

### File Distribution ###

When I need to distribute files too large for email attachments, I use [Sharry](https://github.com/eikek/sharry). It allows for password protected and time limited files, direct downloads or a fancy page with previews, offering multiple files through a single link, and providing a way for others to upload large files to me.  It does all the things that services like sendspace are otherwise known for.  

### Bookmark Management ###

I store both my bookmarks and my reading list in [readeck](https://readeck.org/en).  The major advantage is that it has a browser extension, allowing me to bookmark and save the page my browser actually received.  In the current environment of AI crawlers and website blocking, any bookmarking app without this feature is at a major disadvantage.  While I do wish it had a way for me to publicly share my recent bookmarks, it does absolutely everything else I want from a bookmarks and reading list manager.  

### Bluesky PDS ###

While I agree with the general sentiment that Bluesky is neither federated 'nor distributed, I never the less run a [personal data server](https://github.com/bluesky-social/pds) to take what little control of my data I can.  However, as bluesky allows you to use your own domain without hosting anything, it kind of feels like all I'm doing is saving the for-profit Bluesky corporation a little bit of money on their storage bill.  There aren't any apps that do anything special with a PDS, any way to export your data or keys, or any other advantage to selfhosting on Bluesky.  

### NVDARemoteServer ###

As I do sometimes need to access my machines remotely, I run [NVDA Remote Server](https://github.com/jmdaweb/NVDARemoteServer).  It's an extremely simple app with almost no configuration; I enabled automatic updates, and it's otherwise set it and forget it.  Though with NVDA making the Remote addon part of the main codebase, it's possible that will change in future.  

### Things I'm looking for ###

Currently none of the monitoring dashboards are accessible. Cosmos Cloud gives me the basics, and that's all that I've needed so far.  But if I ever wanted to understand uptime and resource usage by endpoint over several months, I'd be at a bit of a loss.  Similarly, the command line remains the only decent way to examine logs.  

All of the advanced AI testing and usage interfaces are inaccessible. I currently use [SillyTavern](https://github.com/SillyTavern/SillyTavern) with an [accessibility userscript](https://greasyfork.org/en/scripts/503246-sillytavern-screenreader-accessibility-fixes), but it's far from ideal.  I know Taylor Arndt (@tayarndt@techopolis.social) was working on a [more accessible fork of openwebui](https://github.com/tayarndt/open-webui), but I'm not sure how far she got.  

### Things I intentionally don't selfhost ###

I ran my own email server for years.  However, with modern DNS blocklists, and the increasing centralization of email providers, it's just not worth it.  Getting your emails delivered today requires a company with one or more full-time experts working on the problem.  

This blog is, in fact, not selfhosted.  The available selfhosted solutions either had accessibility issues, were overly complicated to configure and build, or had features I didn't want and would never use.  Writing the content is hard enough; I'm just not that interested in setting up a deployment workflow for a static website, building Hugo by hand, or troubleshooting a PHP or NodeJS app.  

More than anything, living productively as a person with a disability requires pragmatism.  We have to balance control, freedom, efficiency, independence, and ability in a delicate dance.  My self-hosting toolbox reflects that ongoing give and take.  My choices might not be right for you; you may want to do much more, or much less.  But if you're growing in tech freedom and agency, whatever you're doing, you're on the right path.  
