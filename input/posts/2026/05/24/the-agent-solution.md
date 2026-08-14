Title: The Agent Solution I Actually Settled On
Published: 2026-05-24
Lead: After bouncing between OpenClaw, Codex, Perplexity Computer, Spacebot, and a bunch of other systems, Hermes Agent is the one I've settled on.
Tags:
- articles
Fedi: https://fed.interfree.ca/notes/amnwg3b4ps68krtm
---
If AI is going to become a regular part of my workflow, I have a number of requirements for how it needs to work. Every single blind person has been burned by services locking down API's, making inaccessible updates, or just getting rid of functionality we depend on. In order to avoid history repeating itself, I want a system that is:

- decomposable: I can replace any of the bits at will
- standards based: AI is moving fast. But there are already a number of standard ways of doing things. The systems I use need to support them.
- cheap and efficient: Most of the giant companies are losing money on AI, and the prices are going to go up rapidly over the next nine to twelve months. That's not to mention the environmental impact of making AI do jobs it's unsuited for.
- Secure: allows management of capabilities, sandboxes, and passwords or API keys never hit the AI.

One of the goals I explicitly didn't mention is privacy. I wouldn't post anything in an AI chatbox that I wouldn't also post to Mastodon or the fediverse. If having your prompt, or the AI response, published for anyone to see could hurt you, you shouldn't be using AI for that. If you think about AI in that light, it makes it much easier to keep up the discipline of not letting it see things it shouldn't, or not letting it access private info.

That said, your data should still be yours. If you're using Chat GPT or Perplexity or one of the major systems, they're both training on your data, and holding it hostage. If you build your own agent, they're still training on your data, but at least you can import it, export it, and do whatever you want with it. It's not locked in their walled garden.

Unfortunately, after a couple weeks of using OpenClaw, it became clear that it was massively inefficient, and wildly unstable. Fed up with spending more time fixing my AI agent than using it, I gave up for a while and just used Perplexity. However, three weeks ago I set up [Hermes Agent](https://github.com/nousresearch/hermes-agent). It updates daily, and has never broken itself, or required anything from me beyond the work I put into setup and configuration.

In order to save you some time, if you're interested in an agent of your own, here are some of the tools and tricks I settled on.

### The Provider and Models ###

The cheapest option I've been able to find is [NANO GPT](https://www.nanogpt.com/). For a $12 a month subscription, it gives you access to more tokens than you'll ever use. However, the subscription only allows you to use open-weights models. So no Gemini, OpenAI, etc. You'll mostly be depending on the cheaper Chinese models. For a primary model, I have no problems with moonshotai/kimi-latest. It never misunderstands tasks, and the writing in its responses isn't too awkward. When coding or using tools, I set my delegation model to zai-org/glm-latest as it tends to make things up a lot less.  For title generation, you can just use a local version of ibm-granite/granite-4.1-8b. Use the same model for command approvals. Set your vision model to Qwen/Qwen3.6-35B-A3B:thinking, and you'll get image descriptions that are fine. Everything else can be deepseek/deepseek-latest; it's super fast and super cheap.

However, nano-gpt has one major problem. In order to keep rock-bottom prices, they cut a lot of corners. Unfortunately, one of those corners breaks tool calling. To make it all work, you need to use [NanoProxy](https://github.com/nanogpt-community/NanoProxy). This is a docker that you run on the same machine as the hermes agent, and all nano-gpt requests need to be sent through it. Just run it and change the Base URL for nano-gpt to use the localhost proxy, and everything will work perfectly.

### The Gateways ###

The best ways to talk to your Hermes Agent are:

- email: I gave it a Google account I don't use for anything else. This is where it delivers cron jobs, and other long-running job results.
- IRC: for talking to your agent while you're out of the house
- OpenAI: when you're on your local network or VPN, enable the OpenAI compatible API. This way you can connect to it from the apps you already use.

### The Apps ###

When you enable the OpenAI compatible API, you can use [basiliskLLM](https://github.com/SigmaNight/basiliskLLM) to connect with Hermes Agent on Windows, and [Perspective Intelligence](https://apps.apple.com/us/app/perspective-intelligence/id6448894750) on IOS. When you're out of your local network, you can forward it emails or use IRC.

### Memory and Plugins ###

I tried all of the memory systems. Some were costly, some were overcomplicated to set up and manage, and some were overly simplistic. I finally settled on hindsight as the best middle ground. It's built into Hermes, it works fine, you don't have to give it a model, and it has just the right number of knobs to configure. However, there's one major issue that nobody tells you about. Not in the Hermes Agent documentation, not in the Hindsight documentation, nowhere! When you're backing up Hermes, if you use hindsight embedded, backing up your .Hermes directory is not enough. You *also* have to back up the folder .pg0 in your Hermes Agent working directory. If you don't, you'll lose all of your memories.

The next thing you need is a plugin called [Hermes-LCM](https://github.com/stephenschoettler/hermes-lcm). If you use cheap models the way I do, you need to be compacting your context when it's 25 percent full, not the default setting of 75 percent. However, that risks your agent forgetting what it's doing, or losing critical info. To solve the problem, Hermes-LCM gives your agent tools it can call to search just the current session, in order to get information back that had to be compacted away to save tokens. Just install it and enable it, all of the default settings are fine.

If you have other servers via SSH that you'd like your agent to access, grab [remote hosts](https://github.com/donovan-yohan/hermes-plugin-remote-hosts). Once installed, you need to add every server the agent can access to config.yaml with a valid authorization key. This way, it can't use regular SSH via the terminal, it never sees SSH identities, and it doesn't know the host and port it's connecting to. It only gets the connection name you gave in config.yaml, and the ability to run commands on that host with the privilege of whatever user you gave it. On the remote host, disable background tasks. The remote host tool runs a command, waits 30 seconds for a result, and disconnects. So if you set up the remote account appropriately, the AI can't run any process that stays running for longer than 30 seconds, can't read or write files other than the ones you specify, and so on. I use this to let it run commands like top, and to read log files for trends, both things that are tricky and time consuming with a screen reader.

Speaking of the command line and keeping things compact, you should also get [RTK](https://github.com/ogallotti/rtk-hermes). RTK rewrites output from all terminal commands your agent runs, making them eighty percent smaller. This saves money, makes your context stretch further, and allows for quicker responses.

If you intend to use Hermes for coding, also get [Hermes Code Intel](https://github.com/rewasa/hermes-code-intel-plugin). This plugin allows Hermes to only examine single functions or statements in sourcecode, rather than loading entire files. Once again, this makes things much faster and cheaper without effecting functionality.

For search, the [KAGI Plugin](https://github.com/fastfinge/hermes-kagi-plugin) is the way to go. The results are cheap, it can extract the content of URLs, and it returns quickly. Unfortunately, it was written by a guy named Sam, and anyone reading Sam's Stuff knows he's a bit of an idiot.

### Conclusion ###

Once you set up all of the above, you'll have an agent that's more capable than Perplexity or any of the other solutions on the market, more accessible than all of them on your desktop and phone, and that you can run for a fraction of the cost (and a fraction of the environmental and other impacts). On top of that, as local models continue to improve, you'll be able to slowly move more and more of your workload off the cloud. If you have a newer mac, you can already move everything using minimax and qwen to your local machine. I suspect that within two years, I won't need cloud models at all.

Hermes can also write and execute scripts on a schedule, that don't use any LLM to run. The vast majority of the jobs I run in Hermes either run no LLM, and just send me emails and chat notifications based on the output of a Python script, or run a Python script to collect up all the data, then have an LLM summarize it all at the end. This means that unlike with openclaw or other systems, you're not running an agent every 30 minutes to check the temperature or look for email. Scripts handle all that, and only call the LLM if something needs to be done. Then the LLM can modify the script once I've decided what should happen, and whenever the same thing happens again, it no longer hits the LLM. Running about 20 different little jobs an hour costs me nothing, until something happens that needs attention.  An example of the workflow:

- my media server keeps crashing
- I have the AI write a script that pulls the uptime, memory, and other data every 15 minutes, and notifies me when it gets over a target
- When it does, I have the AI use the inaccessible table-based terminal commands to determine what process is hogging everything: turns out it is a buggy app that I never-the-less depend on
- Once we find it, I have the AI modify the monitoring script to try restarting that process next time the values spike, before notifying me
- Now my agent takes care of the media server without ever using an LLM, unless restarting the rogue process doesn't help. If it doesn't, we repeat the investigation cycle, and add more to the script.

This is the only way to actually involve AI in your daily life, while not draining your wallet.
