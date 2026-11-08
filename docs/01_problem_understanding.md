# Phase 1: Problem Understanding

**Project:** Netflix Movie & Series Streaming Database\
**Course:** Database Management Systems · **Year:** B.Tech 2nd year ·
**Team size:** 4\
**Database:** PostgreSQL 15 or newer

## 1. Business context

Netflix India needs a reliable database for subscription accounts,
profiles, the movie and series catalogue, episodes, viewing activity,
ratings, My List, and monthly invoices. The existing database has no
documented schema, so the team must reconstruct it from the supplied CSV
exports. The main business goals are to make member-facing screens and
playback operations responsive, support accurate billing and compliance,
and keep analytics usable as viewing activity grows.

## 2. Problems, stakeholders, and workload classification

  ----------------------------------------------------------------------------------------
  Problem        Business need (in    Main stakeholders Classification      Related
                 our words)                                                 queries
  -------------- -------------------- ----------------- ------------------- --------------
  **P1 -- Home   Load Continue        Members /         **Customer-facing / R01, R03, R04,
  screen**       Watching, Top 10, My profiles;         real-time** for     R06, R22, R25
                 List, and            Personalization   profile-specific    
                 genre-based rows     and UI teams      rows; Top 10 and    
                 quickly and return                     genre rows are      
                 the correct titles                     interactive         
                 for each profile.                      catalogue queries.  

  **P2 -- Title  Open a title page,   Members /         **Customer-facing / R02, R05, R07,
  pages,         show its seasons and profiles;         real-time** for     W01
  playback, and  episodes, find the   Playback and      title details and   
  search**       next episode for     Search teams      autoplay; search is 
                 autoplay, and search                   an interactive      
                 titles without                         query.              
                 noticeable delay.                                          

  **P3 --        Find an account by   Members / account **Customer-facing / R10, R24, W03
  Identity and   email regardless of  holders; Identity real-time**         
  profile        letter case, show    team                                  
  switching**    the account's                                              
                 profiles quickly,                                          
                 and apply plan                                             
                 changes correctly.                                         

  **P4 --        Identify episodes of Content strategy  **Reporting /       R13
  Unwatched      a series that have   team              analytics**         
  episodes       no matching viewing                                        
  report**       record. The result                                         
                 must not incorrectly                                       
                 become empty because                                       
                 of NULL values in                                          
                 viewing data.                                              

  **P5 --        Quickly identify     Payments and      **Interactive /     R11, R21, W04,
  Billing        failed-payment       Billing team;     operational** for   W05
  operations**   accounts for retries affected account  retry and overdue   
                 and accounts on hold holders           lists; **batch      
                 with overdue billing                   jobs** for monthly  
                 dates; run monthly                     billing and dunning 
                 invoicing and                          writes.             
                 dunning reliably.                                          

  **P6 --        Detect kids profiles Compliance /      **Reporting /       R14, R16
  Compliance and that viewed content  Trust team;       analytics**         
  trust**        above their maturity parents and       (compliance and     
                 limit and identify   kids-profile      account-sharing     
                 accounts where       users             checks).            
                 simultaneous viewing                                       
                 exceeds the plan's                                         
                 allowed streams.                                           

  **P7 --        Produce useful       Content analytics **Reporting /       R08, R09, R17,
  Content        reports on binge     and strategy      analytics**. W02 is R18, R19, R20,
  analytics at   sessions, completion teams;            an exception:       W02
  scale**        by genre, device     Personalization / adding a title to   
                 usage, Originals,    Marketing teams   My List is a        
                 ratings, and titles                    **customer-facing / 
                 frequently added to                    real-time write**.  
                 My List. These                                             
                 reports must remain                                        
                 practical as viewing                                       
                 grows 20×.                                                 

  **P8 --        Give Finance         Finance team;     **Reporting /       R12, R15, R23
  Finance and    accurate             Support team;     analytics** for     
  support**      cancellation,        members needing   finance reports;    
                 tenure,              assistance        **interactive       
                 active-subscriber,                     operational query** 
                 and                                    for the support     
                 recurring-revenue                      activity console.   
                 reports; let Support                                       
                 inspect recent                                             
                 viewing activity                                           
                 without slow page                                          
                 retrieval.                                                 
  ----------------------------------------------------------------------------------------

## 3. Assumptions

1.  The supplied 11 CSV files are the only source of truth for Phase 2.
    We will inspect the actual rows and headers, preserve every seed
    row, and document any data inconsistency rather than silently
    changing it.
2.  The seed contains viewing activity from **1 January 2025 through 30
    June 2026** and invoices for **January--June 2026**. The workload's
    operational date is **1 July 2026**, as reflected in its date
    filters and July billing operations.
3.  One account represents one paying household and can contain **at
    most five profiles**. Profile-level activity, ratings, and My List
    entries belong to a profile, not directly to an account.
4.  Kids profiles must have a maturity limit of **U or UA7**. For
    compliance comparisons, maturity ratings are treated in the order
    **U \< UA7 \< UA13 \< UA16 \< A**.
5.  A movie has a title-level runtime; a series is made up of seasons
    and episodes, with episode runtimes. A viewing record without an
    `episode_id` is treated as a movie/title-level play; this
    interpretation will be checked against the seed data.
6.  A NULL `leaving_on` means no scheduled removal date is recorded. A
    NULL `cancelled_on` is expected for accounts that have not been
    cancelled; optional phone and payment timestamps will be constrained
    according to the observed data and business meaning.
7.  `viewing_activity.completed` is a stored completion flag even though
    it may be derivable from watched duration and runtime. We will
    retain it because the supplied workload uses it, and document any
    inconsistency found.
8.  `invoices.amount_inr` records the amount charged for that billing
    period. It is retained as an invoice snapshot even if it differs
    from the account's current plan price.
9.  Query results must remain unchanged during optimization, except
    where the original SQL is proven incorrect because of NULL
    semantics; that defect must be explained and corrected.
10. Performance will be judged on the large dataset: member-facing
    real-time queries target **under 5 ms**; interactive rows, search,
    and operations target **under 250 ms**; reports target **under 5,000
    ms**; batch jobs target **under 2,000 ms**. The expected growth is
    approximately **20×**.

## 4. Phase 1 conclusion

The highest priority is fast, correct member-facing access to profiles,
playback, and personal lists. Operational billing and support queries
must also be responsive, while analytics and compliance reports must
scale without repeatedly scanning an unnecessarily large share of the
growing viewing table. Phase 2 will establish the schema and constraints
from the CSV data; Phases 3--5 will measure, optimize, and validate
these workloads without changing the seed data.
