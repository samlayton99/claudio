# Sam's Eval Examples (verbatim, 2026-06-11)

*Historical — Sam's raw words, folded into `evals/` fixtures and specs v4; never edit below this line.*

one guiding principle, a lot of these things could be bad if there are false positives. false negatives are better, and the user will tell claudio the most important things. so we don't want to swing too far and not let claudio be useless, but stopping false positives is better than missing proactive false negatives. although reminders, jobs, etc. need to be the absolute most reliable ever. reliability is a core design principle

My ideas (a lot of these are automations that a person would have to set up, but this is how the system would work with the custom automations.)
1. A friend of mine at prod introduces me to a new person over text message using the  name 1 <> name 2 format. we chat and have a conversation and propose a time. then the new person id is created, they are under the prod role, an event is created with that person and under that role, an automation tied to events with scheduled meetings triggers and updates my google calendar, an expectation is created with a follow up tag to follow up on the day before. 

2. An email comes through from an airline that I am booking a ticket to utah. my messages also show texts between me and my wife that we are going to utah to visit family. events are created for both, the merge one realizes they are the same time and same flight, makes the merge, and creates the event under family for the whole weekend.

3. I quite my job and a bunch of automations and slack channels are now meaningless. I tell it directly and it closes out those windows and retires that role

4. I have been adding new files to a folder structure on my local laptopp (a window) and these are a lot about topology (personal notes I've been taking). it looks at my goals and sees that it doesn't have an apparent help towards what I've been working on. it asks me about it, asks if this represents a new shift in goals/priorities, or am I procrastinating things. (it sees a lot of important and boring things coming up)

5. it notices that in a particular role, I am getting lots of new messages but have been leaving them on read. (say imessages relating to research). it catches this decay, and asks if I am procrastinating or changeing priorities. 

6. I write a new blogpost on substack (a window) and it goes through, thinks about where it belongs in my wiki, and how it relates to my goals and roles, and puts the right pointers in

7. I start scheduling events for roles that are lower priority according to my values. it sees these roles don't relate to my top goals, but some of my lower ones, or not at all. It asks me how it relates, or if I am not prioritizing correctly? it is incessant that I either give an answer to make a new connection in its graph between roles and goals or I accept that I am not being true to my values, and it will give me reminders as a new automation 

8. I log my daily activities on my dashboard. it goes through, adds these as events according to the goals and pushes they inherent (all done for this specific plug in) and ties their roles to that. 

9. I ask for a custom dashboard that has multiple tiles. one tile is an expectations leaderboard, who meets my expectations the most as a percent, and as raw count. etc. then a new tile that tells me how many messages I have been ignoring each day over time. then a new tile with leaderboard of most urgent texts I need to get back to, etc. all these automations are made, using the different windows, mcp, etc. 

10. I have a meeting with someone over zoom, and they mention multiple people in the meeting transcript that I should meet. when the transcript is processed, it looks at the context of that person, the names they gave me, and spawns a web search agent to see who they are (if they can get more context for possible matches) then it sends me a message that asks if I want to connect with the person they mentioned. if I say yes, then it creates an id for that person, gives me a draft to text to the person to connect us, creates a task for me to send that message, and does it all with the correct inherited role. this would be a meeting scanner workflow that would scan all my meetings for the richest connections.
(note that there should be relationships between people that are kept track of (although it will be mostly empty and conservtive). so in this case the correct relationship list will be appended, along with the relationship description as a term of the relationship. so this can be tracked and added, but false positive is worse than false negative. my own relationships with people will be much more clear)


My thoughts on your ideas:

I like them all. really good man. only a few things:
- I didn't really talk about atoms, I agree in my mind they aren't defined well. I think you should handle the best way to figure out the atoms, because they are super important to get right. I don't know the best answer at this point, but it must be well defined
- a vibe check point. you said for your number 10. that the friends chatting is nothing and low signal. friends are very important to me. you are right that it wouldn't really generate things here (maybe that I reached out to them, becuase I would want to configure an agent that helps me keep on top of my friends and lets me see who I haven't connected with in a while). so just note that friends are important to me value wise, but may not induce a lot of tasks, so the actions/steps you took were correct, but the framing seemed a little off.
- one thought with sourcing things out to gcal (12 on yours). often I use it as a draft or a daily planner, and so a lot of things don't happen. some things do, some don't. this shouldn't be a design principle, but be adaptive to the person using claudio. this is a great design principle and should be clearly thought through.
- one thing to think about, role often will come by the window being used. for example all things originating from the prod slack should be given the prod role (inheritance) and imessages will maybe have many roles, but this serves as a dependent type, limiting potential options, making it easier for the agents to judge whate role it is under. 