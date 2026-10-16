## Learn to See VR game

> Implementation reference: [Tasks and task lists](tasks.md) describes the current task architecture, progression and persistence. The prototype architecture below records the original proposal.

Wanchen, Wei, Megan

## 1\. PROJECT OVERVIEW

A VR game, built in Godot for Meta Quest, that trains vision skills in children who gain sight late.   
We are hoping to build the game for children in India (ages 8-18, Project Prakash) treated for dense congenital cataracts, and it could serve other groups with overlapping needs and vision difficulties (low vision, CVI, amblyopia, vision loss after stroke)

### The Perceptual Vision Problem 

After surgery, late-sighted children can see but lack the skills to make sense of what they are seeing: contrast, fine detail, objects in clutter, face identification, and more stay weak for months or years \[1–3\]. Our game aims to turn that practice into a free-world exploration where vision is a superpower you can grow. 

### Why open world

- **Creativity & active learning:** children can freely build, customize, and interact with their own environments  
- **Progressive visual learning:** Children will be able to explore complex scenes in real environments that are grounded in visual concepts   
- **Multisensory integration:** Integrating spatial audio, visual cues, and haptic feedback to help children connect information across scenes   
- **Real-world spatial understanding:** Children will be able to explore freely and practice recognizing landmarks, distances, or object relationships that would take place in the real world.  
- **Motivation & autonomy:** freedom to explore, build, and achieve self-selected goals can encourage sustained engagement.

## 2\. Background

We explore four life domains that will guide our VR activity design, adapted from a questionnaire developed for Indian children with visual impairment \[4\]. People is our addition, inspired by Project Prakash accounts of recognizing loved ones and by research on face perception after sight restoration \[3\].

| Domain | Example activities |
| :---- | :---- |
| Daily routine and objects | Find and handle everyday objects |
| Getting around | Notice obstacles, judge distance, follow motion |
| School and reading | Read shapes, symbols and pictures |
| People \[Team\] | Recognize faces, expressions and gaze |

A potential future domain includes *psychosocial participation*, which tackles navigating social environments and broader social and emotional experiences, but is beyond the scope of our project. 

To decide what to train, we sort vision skills into three layers: visual function, or quality of the image; perception, or what the brain makes of it; and action, using sight to guide movement. CVI research separates basic visual function from higher-level processing \[5\], and the split between perception and action follows Goodale and Milner’s model of separate visual pathways \[6\].

| Layer | Areas | Example skills |
| :---- | :---- | :---- |
| Visual function \[Team\] | Basic visual function | Fine detail, contrast, peripheral vision |
| Perception | Seven CVI perception areas \[7\]; face and social perception \[Team\] | Objects in clutter, recognition, motion, faces |
| Action \[Team\] | Vision for action | Reaching and grasping |

The perception areas come from research on children with cerebral visual impairment \[7\]; rows marked \[Team\] are our additions. Each domain draws on all three layers. 

## 3\. First prototype (due Oct 23)

We hope to explore one perception skill, finding objects in clutter, for our first prototype.

- **Setting:** one large room, a house or a workshop (to be decided). The child is seated and turns and reaches to explore.  
- **Core task:** the guide names an object; the child finds it among other objects and picks it up.  
- **Main skill:** objects in clutter (working pick), with contrast as a difficulty setting. Newly sighted individuals struggled to separate still, overlapping objects for months, and motion helped them at first \[2\].  
- **Difficulty steps:** more objects nearby, more overlap, lower contrast, less motion.  
- **Help:** the guide gives voice instructions and can make the target move or highlight it. Help fades over rounds.  
- **Feedback:** after each pick, the chosen object lifts out so its edges are clear.  
- **Adaptive difficulty:** levels set by hand through the facilitator panel at first; automatic staircase later.  
- **Logging:** time, tries, and help used for every round.  
- **Not in the first build:** story theme, rewards and unlocks, multiple rooms, other vision skills, standing and walking.  
- **Open:** the theme, which objects to use, how many difficulty steps.

User Experience

1. **Controls:** Quest controllers. The child is seated, turns their head and reaches to grab objects, and moves around the room with the controller.  
2. **Feedback:**  
   1. **Correct pick:** the object glows green and lifts out so its edges are clear; the guide responds by voice.  
   2. **Wrong pick:** soft red glow and a gentle sound; the guide encourages another try.  
   3. Feedback is always paired across sight and sound, never colour alone.  
3. **Interface:** audio first, since some children may not read well yet. Instructions come from the guide's voice; controls are built into the world rather than floating menus. A hidden facilitator panel lets the team set difficulty and pick the save.

Essential Components

- **Player and hands:** grabbing, turning, moving. Godot \+ XR Tools.  
- **Room and objects:** the scene and a spawner that places objects at the current difficulty. Godot physics \+ our placement logic.  
- **Task manager (hub):** picks the target, checks the pick, ends the round. Custom.  
- **Difficulty adapter:** sets clutter, overlap, contrast and motion each round. Facilitator panel first, then staircase. Custom.  
- **Help system:** guide hints, target motion or highlight, fading over rounds. Custom, using Godot shaders.  
- **Feedback:** glow, lift-out, sounds. Godot audio and shaders.  
- **Guide audio:** recorded voice lines triggered by the task manager. Godot audio; we record the lines.  
- **Logger:** saves time, tries, and help used per round to a file. Custom.  
- **Interdependencies:** the task manager is the hub. It asks the difficulty adapter for settings, tells the spawner what to place, receives picks from the player, and triggers feedback, the guide, and the logger.

**Why VR**

- **Far beyond a screen:** much existing vision training uses flat screens that cover only a small central area. A headset (about 110° wide on Quest 3\) can place objects off to the side and train peripheral vision.  
- **Real depth:** stereo 3D and head movement give depth cues a flat screen can't.  
- **Control over what the child sees:** contrast, clutter, motion and depth adjusted precisely per child.  
- **Hands and body in the task:** reaching and grasping, like real life.  
- **Repeatable, safe practice:** scenes reset and vary endlessly.  
- **Immersive:** a world kids want to explore, supporting practice over many sessions.

Software Architecture

*(Architecture figure omitted; see the original Google Doc.)*

Figure: Tentative architecture loop for Prototype 1\. The task manager is the hub. Each round, it gets settings from the difficulty adapter, has the spawner place objects, checks the child's pick, triggers feedback and the guide, logs the round, and passes the result back to adjust the next round. Later, this can be adapted by adding new task modules triggered by player activity, and feeds into the task runner.

## 4\. Development Roles

Everyone contributes across areas, with one lead per area:

- **Megan: world building, assets and visual style.** Mood boards, concept sketches, assets split into movable parts. Possibly physics for grabbable objects.  
- **Wanchen: story, gameplay and perceptual research.** Storyboarding; researching candidate vision tasks, help and training progression.  
- **Wei: coding and technical implementation.** Leads the build: task manager, difficulty adapter, interaction, logging.  
- **Shared:** building the first scene together, playtesting, recording the guide's voice lines, weekly check-in.  
- **Order:** first scene first; backyard and butterfly task after.


## 5\. Schedule, milestones, deliverables

- **Oct 14–16:** design doc revision 1 and design review slides. After Aubrey's review, decide the first scene (house).  
- **Week 1 (by Oct 23), prototype 1:**  
  - Must have: first scene as a gray box room with placeholder objects, grabbing, one search task, green/red feedback, facilitator difficulty panel, basic logging.  
  - Megan: mood boards and kettle asset. Wanchen: storyboard and task research. Wei: core build.  
  - Stretch: small outdoor area with the butterfly.  
- **Week 2 (by Oct 30), minimum demo:** polish the scene, swap placeholders for real assets, record guide lines, add fading help, first team playtests. Reach out to Professor Sinha with the demo.  
- **Week 3 (by Nov 6):** iterate from feedback; automatic staircase; butterfly task if not done; playtest with classmates.  
- **Week 4 (by Nov 13):** finalize; first unlock (new area or ability); simple no-help check-in.  
- **Nov 13–20:** bug fixes and demo prep. Demo day Nov 20\.


**Combining our work**:

- Shared Git repository; each lead reviews changes in their area.  
- Weekly sync to merge work and playtest together.  
- Everyone builds against the same scene structure (room plus plug-in modules).

## 6\. Getting advice from others

- **Realistic:** course TAs, MIT VR club, Aubrey Simonson (design review), guest lecturers from the class.  
- **Within reach:** Professor Pawan Sinha and the Project Prakash team (MIT)  
- **Aspirational:** Ehud Zohary's lab (Project Eyeopener, Ethiopia); The iVision team (KU Leuven and VUB, CVI games); Luminopia (FDA-cleared VR amblyopia treatment); Meta Reality Labs accessibility team.

## 7\. References

\[1\] Kalia, A., Lesmes, L. A., Dorr, M., Gandhi, T. K., Chatterjee, G., Ganesh, S., Bex, P. J., & Sinha, P. (2014). Development of pattern vision following early and extended blindness. *Proceedings of the National Academy of Sciences, 111*(5), 2035–2039. https\://doi.org/10.1073/pnas.1311041111

\[2\] Ostrovsky, Y., Meyers, E., Ganesh, S., Mathur, U., & Sinha, P. (2009). Visual parsing after recovery from blindness. *Psychological Science, 20*(12), 1484–1491. https\://web.mit.edu/sinhalab/Papers/VisParsing\_PsychScience\_2009.pdf

\[3\] Gilad-Gutnick, S., Hu, H. F., Dalrymple, K. A., et al. (2024). Face-specific identification impairments following sight-providing treatment may be alleviated by an initial period of low visual acuity. *Scientific Reports, 14*, 17374\. https\://doi.org/10.1038/s41598-024-67949-z

\[4\] Wadhwani, M., et al. (2022). Development of age-appropriate vision function questionnaire for children with visual impairment (CHVI-VFQ). *Indian Journal of Ophthalmology, 70*. https\://doi.org/10.4103/ijo.IJO\_1177\_21

\[5\] Chandna, A., Wong, M., Veitzman, S., Menjivar, E., & Kulkarni, A. (2024). Higher visual function deficits are independent of visual acuity measures in children with cerebral visual impairment. *Frontiers in Human Neuroscience, 18*, 1451257\. https\://doi.org/10.3389/fnhum.2024.1451257

\[6\] Goodale, M. A., & Milner, A. D. (1992). Separate visual pathways for perception and action. *Trends in Neurosciences, 15*(1), 20–25. https\://pubmed.ncbi.nlm.nih.gov/1374953/

\[7\] Ben Itzhak, N., et al. (2021). Quantifying visuoperceptual profiles of children with cerebral visual impairment. *Child Neuropsychology*. https\://doi.org/10.1080/09297049.2021.1915265

