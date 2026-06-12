# Sam review
This is where I am documenting and mapping all of my thoughts to your specs.

## before you begin. 
First, do you think this is actually useful to build? am I wasting my time here? if you genuinely thik so, please tell me. I have many other important things to do. this is not a time to be sycophantic. (don't go ahead and do the huge overhaul yet, first answer this question honestly. I want the truth.)

Second, there are some open ended design questions I left for you. I want you to consolidate them in one place, how you think we should answer them, and then tell me the open ended questions you have beneath. after this section, you should also produce a summary/change log of what genuinely changed on this pass (where it was before, where it is now) and the reasoning behind it. Think of it like a diff log. I will be operating only out of that for the final version (have it point to things in the other docs, I won't do another full sweep)

Third, how do you feel bout these design choices? I feel very strongly about most of them. will you please tell me exactly what you changed based on what I said? If you think this is worth building, lets go in, read through this doc line by line, do the passes as directed, and produce v3 along with the diff doc.


## 00 - constitution
I really like where this is at so far

### the decay test
there should be a really good protocol that doesn't require looking at repo. maybe a handshake protocol with a dedicated agent that is meant to find its place in the automations and workflow. this should be gated by user approval/permissions.  clearly explains the current ecosystem, what is going on in sam's life right now. it is a conversation between the handshake agent, representing context, etc. (note this would have to have some safety protocol as in getting spinned up in a sandbox with no external connections so that it prevents security) so these agents talk to each other, figure out where it belongs in claudio, what role, triggers, windows, or datastreams it fits into, and then places it with very well defined scope, context retrieval, and other wiring. It audits against all other automations and makes sure that automations and agents are mutually exclusive, collectively exhaustive. it also make sure that it handles redundancies correctly depending on level of importance (I get that contradicts mece, but automations should have redundancy tags if they violate mece, that is how we will square this). So there should be a handshake agent that has the honest audit of the current ecosystem, is security aware, and does the correct scoping and placing into the current system.

### principle decision map
- is there any way to make the type system stronger? I think for sytems with the potential to sprawl like this, the type system should be one of the primary laws for everything. strongly typed, nothing exists without a typecheck. that should be the law (I haven't done much software design, but when so much of it is non deterministic, I think having the strongest standard of deterministic gates is the only way to make these types of systems usable)

- confidence is often poorly judged by LLMs, so that should fall in taste. the default in design should be low confidence unless glaringly obvious. this is an important design principle, and one that is at tension with the adhd principle. 

### vocabulary
- I don't know if this is already in the design, but approvals/permissions (once flagged) should be deterministically handled.
- I like the dictation gate, doesn't have to be imessage though. 




## 01 - Schema
- This can be run on a mac mini, but we should also let this be run on a vps if desired, (or even maybe in the future, it could be a company/product on its own and we host it for them. food for thought.) but the idea is that the testing ground and mvp is for the mac mini, but design specs and decisions should never prevent a change in envrionemnt or how it is hosted, etc. 

- I don't want to build all of this plumbing/tagging, etc. that agents have a hard time using. so just keep in mind that this is the tickiest part that neds to be clean. it needs to be so so so freaking clean for agents to use well. It needs to be the most intuitive structure for them to work through. traversal here of both the database, and the wiki needs to be the most high quality product. It can't hallucinate, it can't miss pointers, it needs to be token efficient. I know there is a lot of research on how to do good graph traversal. there are two sides to it. a very clear and well defined graph + well defined interface (not just a json dump and let the agent figure it out), and very smart agent traversal protocol. i think these need to be more well researched on your end for the best way to do this. I believe parts of the schema will change downstream based on your findings.  

- make sure the relational database is very clearly mapped. this should be an emphasis, so that anyone looking at the docs can see this both in writing and visually. many to many relationships, etc. 

- goals should really be sitting at the top of the heirarchy. in the end, everything goes back to serving goals. I haven't very well defined them for you, which is my bad. In fact I think it should be broken up like this. there should be a purpose database. purpose includes goals, values and attributes. So we can add goals, change and add values, and have attributes that we are working on. say I want to be a better leader, more christlike, more humble, these are attributes. say I value justice, I value freedom of speech, I value spending time with my family. lets say I have a goal to get a job at spacex, or ipo my company, or solve poverty in malawi, or get more lds people in places of power, or build zion/prepare for the second coming. okay, here is the format. purpose includes: goals, values, attribute_goalposts, and a priorities list. following the adhd principle, there should be a single markdown where you write what is most important to you in your life. then you have an extremely important agent that works with you to help you translate this document into the highest level values. this will be a higher point of friction, but will be worth it. the point is introspection. value alignment, and getting a sense. this field/section/db is the most important for understanding the person and is the highest privelage. nothing can change it. This is the ultimate typechecking contract. this should be maintained, updated, and be so very tuned into the individual. I can't stress this enough. This contract is the law for the whole system. it's not just goals, but the highest level of abstraction, of what is important to that person. the user experience here is so important. they need to FEEL understood. they should feel like they learned something about themselves. That said, once this contract is in place (and given it will continually evolve as the system is proactively trying to work with the user to maintain the quality of this db) there should be a second one that is the tracking db. you could think of this as the typecheck against what is there in reality. they proclaim, they want, the believe these truths, but do they live it? so there needs to be a way to track reality against this, and this will be the greatest source of accountabiliy, be the real moat in identifying and proposing automations, and everything. this is the key that makes this product actually useful. life purpose as a typecheck against reality. every documentation, automation, etc. is downstream of that. (note, the depth of this portion will vary much by user, so the agent should be so high quality and in tune with the user. they should be able to tell when the user doesn't want to go any deepr, or if they are breaking real ground here. does the user just want to use this to help with their emails, or are they actively trying to change their life and this is the tool they finally need to make it happen. This is the ONLY time the model will own taste and it is CRITICAL to get it right. the model should be able to mirror the user so well in this exploration in filling out the purpose database. this is the single highest leverage point of the product, and sets the tone for everything else.)

- the biggest risk to atoms is that the summaries are stale, incorrect, and hallucinations happen. I am declaring this principle going forward. The fundamental law of LLMs is: quality drops exponentially with the number of nested/composed summaries. The proof for this is their lack of taste in being able to preserve what is important. I am concerned that the fundamental atoms here are summaries, this just adds an extra layer of quality decay. Maybe this is unavoidable, but this is something that needs to be considered. 

- how are we configuring the agents that maintain, run and build the system? obviously agents will improve, these should be swapable by design so the product improves with the design. 


## 02 - L1 API
- note, it is important to make a distinction in the docs between internal writing back and forth to the system, and external writes (like sending an email through an agent that has that capability). and along that vein, approving message/external write capabilities should be entirely outsourced to agent endpoints. maybe we create a special tunnel directly to them and have a protocol that allows that? let me know what you think. I just want a clear boundary with write. this is crucial for trust. 

- one principle is that names must be super descriptive for mcp and other agents to use well. so see if there is an improved renaming directive we can do.

- another thing, for the automations we create and own, vs external tools, there will likely need to be an efficient way to plug this in. we should have a standard internal format, with agent harnesses or external automations (not to be confused with an agent's own harness, but our personal harness) that can fit and be configured for any workflow or automation. so everything speaks the same language on the inside across the wire, custom tools, external agents, or even like a zapier call to some externally derived automation could be fit in. (if making this really good is out of scope for now, that's fine, but there should at least be this separation of external vs internally built automations)

- merge decisions should be tunable. I feel like this is something we are going to have to iterate on in practice

- note that retiring a role, should not retire wiki pages, it should still be traversible, but there should be a default filter for active roles, and the scaffolding agents can choose to look through past roles if necessary/useful

- ya, as far as like proposing messages, I am just hesitant. it will create a lack of trust for the user. this is not meant to be an operator, but a central hub that agents can work together. so like, lets say an event happens, and there is a potential external write or an email draft, then an email triage drafting agent should be informed of what is going on, and then it owns drafting it up and sending that draft through its own preconfigured channels. (so I have one central brain, which is claudio, and the the other agents reach out to me personally for approval/sending. again, maybe setting up a pipe to do that is an option, idk what do you think?)

- context package needs really high quality. I like how it is now. I think we just need to be careful so that agents are not seeing things they don't need. maybe a verbose option for agents to call or not, idk. 


## 03-runtime.md
- latency obviously shouldn't be super long. the main interface agent should be quick, and be clear about progress of what is going on. So latency is fine on the internals, so long as it doesn't negatively effect the user experinece. 

- think the assembler should be an important agent. basically it looks at the context, gets everything, and should traverse the graph a little more to see if there are things that it missed. this should be a two pronged approach. go look at the graph traversal section. 

- again, cron times, etc. should be set in the core configurations. 

- queues should be very good with race conditions. they must be 100 percent reliable.




## 04 - securtiy
I don't know much about security. I trust your judgement to make it both good and not overkill.


## 05 - wiki.md
one note on boundary rule, I like it, but the DB should have sufficiently descriptive language that agents can scaffold it well. so regardless, the DB needs probably be more descriptive than you currently are making it sound. that is important. 

second thing, I know others have worked on personal wikis before. go research online about what ones were made, what were some of their design principles, and what ones were actually successful. this is crucial. we cannot have a poorly implemented wiki. a failed product otherwise. both the scaffold, the interface, the connections, the way connections are managed, the write, the append, the udpate, all of it needs to be highest quality, so see what has actually worked in the community (stars on github are a good signal) and then filter what you learn against what makes sense in this context. (also don't just blind copy what they did) this is in relation to the graph traversal research you will be doing.

wiki pages should not be created for DB events. that is bad scope. The wiki should in some sense read like wikipedia, and be human traversible. an hour long meeting with a potential investor should be distilled into an atom, with pointers to the transcript, and probably a new line in a wikipage (along with a pointer to the conversation) of current investors that sam is talking to. However, major life events can be wiki pages (like the death of a family member, or getting married/wedding) but these should only be things that are significant or useful context for future agents. 

so maybe a reframe. the wiki is not a one to one in the database. the wiki is consolidated source material to understand broader context. yes, it has strong correspondance with the DB, but it also is a sort of biography. think, if sam, sam in 6 months, or people in sam's circle doesn't find this intereting or useful, maybe it shouldn't be a wiki page. maybe this means we need another datastructure for the 1 to 1 correspondance. but I think we are off on what the wiki does vs me. so we need to rethink the types of pages/wiki structure. maybe: people, personal life, significant events, professional life, purpose (this could have lists of beliefs over time, or also store the lived purpose vs proclaimed purpose discrepencies), progress, interests, lessons learned, personal pitfalls (problems I keep causing myself), how to work with sam (this one could be an internal use for agents to reference so that the system gets better over time). these are not all mutually exclusive, but something like this can be better thought out. this is the record of my life, experiences,  and taste. 

maybe we do weekly and monthly summaries that incorporate current state (that's actually a great idea. we should have weekly monthly, and bi annual summaries to record the general state of the person's life. this is an audit that is updated regularly, and fed into general context across many agents. I think this would be helpful)

when consolidating, updating, writing new pages, raw atoms should always be in the context window. pages with new events, should have the general direction/reason for update in the prompt and loose direction of proposed chagnes, the previous version, and a full list of atoms (fundamental theorem of LLMs). 

the datatype for wikipages needs to be well thought out. right now it is not.

yes, the heirachy is super important here.

note, atoms can be assigned to multiple wiki pages.

i like your factual storage. judgement is reserved, facts are presented. 

## 06 - surfaces
imessage doesn't have to be the pimrary entry, it can be whatever we configure it to be (this goes back to the, do we build a custom entry point? where does it live?)

again, proactive pushes should be set as a parameter.

orchestrator should be configurable. idk if claude code is the best. maybe hermes, maybe claude agent sdk, who knows. up to the user. (general note that most of these agent choices should be configurable. the less hardcoded in, the better.)

Idk if the approval gate should only live in the panel. I think the verifier/approval agent should actually be its own channel. but again, configurable. 

changes made in the panel should be able to override anything, and should be tagged that the user made the changes. for exmaple, editing a wiki from here makes it a permanent artifact. this is the zoom in control, edit, that the user can input that is law. this should be the human window into the sytem. inputs from users at this panel level receive the highest authority clearance. changes are the ultimate taste and should persist if they were input through this channel. obviously should be easy to navigate and search. we can build the v1 core functionality, but I will iterate on the design with claude design.

should include a chat interface here as well. and a place to ask questions, run custom research about events, wikis, etc. this is a place for the user to interact with the system.

Custom dashboards can also build some functionality, (say I want to track a metric that doesn't exist explicitly but could exist, I can have that metric owned in the dashboard)

## 07 - build plan
you can also use your test scenarios. note that the evals are not law, you can build and add to them as you please. if scope changes, then evals should too.

the build plan will obviously need to be updated for v3. one thing to think, is build folder structure, and high level layouts first, types and contracts second, functionality and wiring third. 

finally, constantly be revisiting the core build principels. independent audits should run and surface things as they get built. scope/fat should consistently be trimmed, and asking me questions is always a good idea. 

## answering your questions
1. if you think its worth it, go for it. but occam's razor is king. 
2. accept
3. I'm not sure if i am following, I don't know how relevant this is anymore. I'm hesitant to say yes.
4. the primary chat chanel will have equal clearance with the pannel, but the panel edits and changes take priority over anything from the chat. so think equal clearance, deference to panel as ultimate authority.
5. ummm, I think some things might benefit from a router daemon. (like the main chat interface, but again this hasn't been settled yet.)

there should be some sort of consolidation/pulse on everything that has happened in the day. events shouldn't be the only atom. maybe we need to think more about atom granularity, live updates, and consolidation. this is because, one day I could have a huge inbounds of texts, and I don't want everything else to be drowned out. but I want to record the right amount of atoms, and have them point to the raw. so what are your thoughts? this is an open question, one that is not resolved.

I like a relationship vocab seed. where it makes sense, we should add vocab seeds (but be very conservative) and make these be the strict flags. flags should be very conservative as they are hard to label and hard to maintain. so any flag creation that is filterable, should have a strong type system, be very conservative in the number of available tags, require OS (me in claude code) to edit them, be very obvious in nature and well documented what they get applied to, and always have a default unknown that agents are instructed to bias towards. 


## Other General thoughts
- there should be a special, primary entrypoint (could be an agent or just a simple pipe) that is required and has the ground zero permissions. this designated agent's only job is to work directly with the user as a pipe. so for example, it could be poke if you want the main entry way to be in imessages. but this should be required

- there also needs to be very clear budget control. there should be a way to route intelligence to the right tasks (cheaper models, etc.) making this fine grained is going to be very difficult, so it should be high level. but having stupid agents or models when it should be really smart ones is a huge weakspot. so that needs to be thought of carefully

- assync, disruptions, backups, these need to be handled well. especially race conditions. a core principle is cleanest input ever. we want the maintainers to be spending as little tokens as possible. every maintenance gardner should be seen as a downstream failure of the system. build in this tension. gardners are eager to maintain (and the system promotes that) but the design is unforgivingly robust so that gardners are being minimized as much as possible. think of it as a minimax problem.

- there should be a master password/codeword that is hidden from all aspects of the system, except for a special verification agent. this should have its own 2fa pipeline etc. keep this in line with the design principle of adhd.

- any agent that is known to have write access should be treated differently than agents that don't have write access. this should be clarified and diagnosed in the handshake process. this should be probed very cautiously for security reasons. there's a chance a malicious agent would want to hide this fact, so this distinction is super important. maybe a user permission gate.

-on second thought. given the security stuff, maybe we should just have a dedicated channel, one that exists in iphone, email, chatbot, etc. outsourcing the primary entry way to another agent is starting to feel risky to me. what are your thoughts?

- there are a lot of hardcoded parameters, and will be many many more parameters that will pop up as we start developing this. quality will likely depend on this. there should be a unified place to control parameters. they should be split by the core, and everything in the outer ring. the core parameter fields don't change, but the parameters for the outer ring will change. that is the separation. but this should be centralized. same idea also goes for access tokens, api keys, etc. the core, and the outer ring

- there should also be guardrails/downward pressure to prevent unnecssary token spend. 

- there actually should be a second agent that has taste. this should be the usage monitor agent. this one should be very actively paying attention to the user, and what the user is actually using and what it isn't. it's goal is singular, get the user to actually benefit from the system according to its goals. So they are picking, and promoting ideas of how to build the right automations, and what automations to cut to save the user token usage. This should be conservative, with really good taste, and really closely follow the users usage patterns, and also frequently interact with the user. maybe this agent is the same as the one that builds the purpose graph. easier to own taste in one? give me your thoughts.

- there should be a way for the system to prompt suggestions of windows to connect the more windows it has, the better the system is. (one that i thought of just barely, maybe setting up a claude code and claude.ai chat recon ingester, that measures the projects, the time sent, the number of prompts, and rough overview of the content. that would be a great window to include into this system that gets digested, and I would want the system to be able to suggest that if it picks up I am coding on claude code like 8 hours a day). but use the terminology of "windows" I think there are a lot of agents and stuff that do things, but windows is a category that specifically leads to data ingestion and is assigned a role (there should also be a general role). but windows should be treated specially and differently than agents/automations/workflows

- also want to see a very clearly mapped out place where I can look at and audit all my agents/automations/workflows and what the system defines their roles as, as well as their usage in practice.

- didn't see much planned in terms of inheritance. inheritance just makes things easier so that llms don't have to make as many judgement calls about where things belong.


## general directives for the next pass (probably spin off agents to do this, lots of these things should be promoted as core design principles too)
- think about how to incorporate everything I said above. (especially the directive about purpose db, but look at everything)

- (2nd most important) I want you to look at this now from a UX perspective. this needs to be the absolute, most simple thing to use, maintain, and grow with. This needs to be effortless. that is the key word for the user. I want you to walk through everything, document the exact clicks, setups, debugging, etc. that will be required on the user. do this as is in the current version. Put it into tiers/rings of core required steps to even set it up, a ring representing the bare minimum steps/maintance required to even get use out of it, the steps/maintenance required to get meaningful use out of it, and the steps/maintence required for full feature functionality. This list is now your sins. it should be as small as possible to achieve the same ring of functionality. Think of this is a complete UX audit. Also have an ADHD filter, so that it captures the failure points of someone with even the most severe adhd who can't reliable work or maintain systems. think about how this affects the overall design. hypothesize what wins we can have in both setup, maintainence, and integrations. seamless, effortless, capable. After you audit everuthing as is though this lens, start thinking of solutions. think of how to trim down the rings, think of what users would actually find useful, think of ways to remove all forms of friction. This deserves a lot of thought and if done well, will cause significant overhaul. 

- (third most important) a travesal quality pass. the two sidews here. it needs both the representation to be so natively intuitive to these agents. not a json dump of options, but the right natural language, the right in context examples, the right interface for it. that's one side, the second side is the traversal protocal. the agent needs to be seeded, can grep, can add things to queue, can do semantic search/rag style. the point is this. this is basically an open problem, and for it to be good, there needs to be a lot of research on your end on what actually works. we should make this representation and the protocol more explicitly defined for the agents. go look up the research, the research that is actually cited, the research that people are actually implementing and using, and figure out how to attack both sides to this problem. this pass is crucial.

- (fourth most important) the entire project should be looked through the lens of the fundamental law of LLMs: quality drops exponentially with the number of nested/composed summaries. how does the overall system take into account and safeguard against this law?

- (5th most important) dependencies are death. there should be a sweep to outline every agent and process dependency. how much can be done async? the whole structure should be as async as possible, designed in a way to limit dependencies. think of dependencies as bottlenecks, and chained dependencies are even worse. this should be mapped out and then carefully crafted for. user dependencies will likely be tricky here for this exact reason. 

- (6th most important) doing a solid research on the wiki.

- (7th most important) stronger type system check. this may be redundant, but maybe one way to frame it is that the typesystem is the prodcut. what are your thoughts here? 

- (8th most important) the gardner—design tension. there should be a sweep over the whole plan with this in mind. the design is doing everything it can to prevent gardners from having work to do, but the system is doing everything it can to make sure that gardners are being dutifully deployed. This lens should be looked at with a fresh eye.

- (9th most important) there should be a descriptive name rewrite scan. this goes back to the principle, if function calls, names, etc. are going to be called by agents, clarity is king. so see what names, functions, and descriptions should be made more clear. this should be a core principle.

- (10th most important) this whole system should be security tested against a secrete malicious, agent. think, if a superintelligent agent was trying to access any of my data, act in my behalf, or alter data that was in my pipeline for malicious purposes, how would it weasle its way in? this will have an interesting security perspetive.

- (11th most important) hosting environment directive. this should be iterated on assuming the mac mini environment, but design principles should be model agnostic (run on a linux in a vps or be hosted by a future company if this gets sold there, etc.)


- (1st most important) after this is all done, there needs to be a final over engineering pass. I have the habbit of tyring to build things out theoretically before actually iterating on them in person. Assume that half of this will be eventually discarded and thrown away. we don't know what, but this is an important filter. simplify, simplify, simplify. is everything load bearing and earn its place? ask yourself if we really need this. trace it back from first princples. this is the ground to earth, make sure it stays real, and is founded on first principles, rather than the ideas in sam's head that he gets excited about. this is the most important step. 
