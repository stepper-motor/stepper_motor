## Intro

`stepper_motor` solves a real, tangible problem in Rails apps - tracking activities over long periods of time. It does so in a durable, reentrant and consistent manner, utilizing the guarantees provided by your relational database you already have.

## Philosophy behind stepper_motor

Most of our applications have workflows which have to happen in steps. They pretty much always have some things in common:

* We want just one workflow of a certain type per user or per business transaction
* We want only one parallel execution of a unique workflow at a time
* We want the steps to be explicitly idempotent
* We want visibility into the step our workflow is in, what step it is going to enter, what step it has left

While Rails provides great abstractions for "inline" actions induced via APIs or web requests in the form of ActionController, and great abstractions for single "unit of work" tasks via ActiveJob - these are lacking if one wants true idempotency and correct state tracking throughout multiple steps. When a workflow like this has to be implemented in a system, the choice usually goes out to a number of possible solutions:

* Trying ActiveJob-specific "batch" workflows, such as [Sidekiq Pro's batches](https://github.com/sidekiq/sidekiq/wiki/Batches) or [good_job batches](https://github.com/bensheldon/good_job?tab=readme-ov-file#batches)
* State machines attached to an ActiveRecord, via tools like [aasm](https://github.com/aasm/aasm) or [state_machine_enum](https://github.com/cheddar-me/state_machine_enum) - locking and controlling transitions then usually falls on the developer
* Adopting a complex solution like [Temporal.io](https://temporal.io/), with the app relegated to just executing parts of the workflow

We believe all of these solutions do not quite hit the "sweet spot" where step workflows would integrate well with Rails.

* Most Rails apps already have a perfectly fit transactional, durable data store - the main database
* The devloper should not have intimate understanding of DB atomicity and ActiveRecord `with_lock` and `reload` to have step workflows
* It should not be necessary to configure a whole extra service (like Temporal.io) just for supporting those workflows. A service like that should be a part of your monolith, not an external application. It should not be necessary to talk to that service using complex, Ruby-unfriendly protocols and interfaces like gRPC. It should not be needed to run complex scheduling systems such as ZooKeeper either.

So, stepper_motor aims to give you "just enough of Temporal-like functionality" for most Rails-bound workflows. Without extra dependencies, network calls, services or having to learn extra languages. We hope you will enjoy using it just as much as we do! Let's dive in!

## A brief introduction to stepper_motor

stepper_motor is built around the concept of a `Journey`. A `Journey` [is a sequence of steps happening to a `hero`](https://en.wikipedia.org/wiki/Hero%27s_journey) - once launched, the journey will run until it either finishes or cancels. A `Journey` is just an `ActiveRecord` model, with all the persistence methods you already know and use.

Steps are defined inside the Journey subclasses as blocks, and they run in the context of that subclass' instance. The following constraints apply:

* For any one Journey, only one Fiber/Thread/Process may be performing a step on it
* For any one Journey, only one step can be executing at any given time
* For any `hero`, multiple different Journeys may exist and be in different stages of completion
* For any `hero`, multiple Journeys of the same class may exist and be in different stages of completion if that was permitted at Journey creation

The `step` blocks get executed in the context of the `Journey` model instance. This is done so that you can define helper methods in the `Journey` subclass, and make good use of them. A Journey links to just one record - the `hero`.

The steps are performed asynchronously, via ActiveJob. When a Journey is created, it gets scheduled for its initial step. The job then gets picked up by the ActiveJob queue worker (whichever you are using) and triggers the step on the `Journey`. If the journey decides to continue to the next step, it schedules another ActiveJob for itself with the step name and other details necessary.

No state is carried inside the job.

## Installation

Add the gem to the application's Gemfile, and then generate and run the migration

    $ bundle add stepper_motor
    $ bundle install
    $ bin/rails g stepper_motor:install
    $ bin/rails db:migrate

## Usage

Define a workflow and launch your user into it:

```ruby
class SignupJourney < StepperMotor::Journey
  step :after_signup do
    WelcomeMailer.welcome_email(hero).deliver_later
  end

  step :remind_of_tasks, wait: 2.days do
    ServiceUpdateMailer.two_days_spent_email(hero).deliver_later
  end

  step :onboarding_complete_, wait: 15.days do
    OnboardingCompleteMailer.onboarding_complete_email(hero).deliver_later
  end
end

class SignupController
  def create
    # ...your other business actions
    SignupJourney.create!(hero: current_user)
    redirect_to user_root_path(current_user)
  end
end
```

## A few sample journeys

### Single step with repeats

Let's examine a simple single-step journey. Imagine you have a user that is about to churn, and you want to keep sending them drip emails until they churn in the hope that they will reconvert. The Journey will likely look like this:

```ruby
class ChurnPreventionJourney < StepperMotor::Journey
  step do
    cancel! if hero.subscription_lapses_at > 120.days.from_now

    time_remaining_until_expiry_ = hero.subscription_lapses_at - Time.current
    if time_remaining_until_expiry > 1.days
      ResubscribeReminderMailer.extend_subscription_reminder(hero).deliver_later
      send_next_reminder_after = (time_remaining_until_expiry / 2).in_days.floor
      reattempt!(wait: send_next_reminder_after.days)
    else
      # If the user has churned - let the journey finish, as there is nothing to do
      SadToSeeYouGoMailer.farewell(hero).deliver_later
    end
  end
end

ChurnPreventionJourney.create(hero: user)
```

In this case we have just one `step` which is going to be repeated. When we decide to repeat a step (if the user still has time to reconnect with the business), we postpone its execution by a certain amount of time - in this case, half the days remaining on the user's subscription. If a user rescubscribes, we `cancel!` the only step of the `Journey`, after which it gets marked `finished` in the database.

### Email drip campaign

As our second example, let's check out a drip campaign which inceitivises a user with bonuses as their account nears termination.

```ruby
class ReengagementJourney < StepperMotor::Journey
  step :first do
    cancel! if reengaged?
    hero.bonus_programs.create!(type: BonusProgram::REENGAGEMENT)
    hero.push_anayltics_event!(event: "reengagement_touchpoint", properties: {step: 1})
  end

  step :second, wait: 14.days do
    cancel! if reengaged?
    hero.bonus_programs.create!(type: BonusProgram::DISCOUNT)
    hero.push_anayltics_event!(event: "reengagement_touchpoint", properties: {step: 2})
  end

  step :third, wait: 7.days do
    cancel! if reengaged?
    hero.bonus_programs.create!(type: BonusProgram::DOUBLE_DISCOUNT)
    hero.push_anayltics_event!(event: "reengagement_touchpoint", properties: {step: 3})
  end

  step :final, wait: 3.days do
    cancel! if reengaged?
    hero.close_account!
    hero.push_anayltics_event!(event: "reengagement_touchpoint", properties: {step: 4})
  end

  def reengaged?
    # If the user purchased anything after this journey started,
    # consider them "re-engaged"
    hero.purchases.where("created_at > ?", created_at).any?
  end
end
```

In this instance, we split our workflow in a number of steps - 4 in total. After the first step (`:first`) we wait for 14 days before executing the next one. 7 days later - we run another one. We end with closing the user's account. If the user has reengaged at any step, we mark the `Journey` as `canceled`.

### Archiving and deleting user data

Imagine a user on your platform has requested their account to be deleted. Usually you do some archiving before deletion, to preserve some data that can be useful in aggregate - just scrubbing the PII. You also change the user information so that the user does not show up in the normal application flows anymore.

```ruby
class AccountErasureJourney < StepperMotor::Journey
  step :deactivate_user do
    hero.deactivated!
  end

  step :remove_authentication_tokens do
    hero.sessions.destroy_all
    hero.authentication_tokens.destroy_all
  end

  step :archive_pseudonymized_data do
    DatapointArchive.create(name> "user-#{hero.id}-datapoints.gz") do |io|
      CSV(io) do |csv|
        csv << hero.datapoints.first.attributes.keys
        hero.datapoints.each do |datapoint|
          csv << Pseudonymizer.scrub(datapoint.attributes.values)
        end
      end
    end
  end

  step :delete_data do
    hero.datapoints.in_batches.destroy_all
  end

  step :send_deletion_email do
    AccountErasureCompleteMailer.erasure_complete(hero).deliver_later
  end
end
```

While this is seemingly overkill to have steps defined for this type of workflow, the basic premise of a `Journey` still offers you substantial benefits. For example, you never want to enter `delete_data` before `archive_pseudonymized_data` has completed. Same with the `send_deletion_email` - you do not want to notify the user berore their data is actually gone. Neither do you want there to ever be more than 1 process executing any of those steps.

### Performing an outgoing payment

Another fairly widely known use case for step workflows is initiating a payment. We first initiate a payment through an external provider, and then poll for its state to revert or complete the payment.

```ruby
class PaymentInitiationJourney < StepperMotor::Journey
  step :initiate_payment do
    ik = hero.idempotency_key # The `hero` in this case is a Payment, not the User
    result = PaymentProvider.transfer!(
      from_account: hero.sender.bank_account_details,
      to_account: hero.recipient.bank_account_details,
      amount: hero.amount,
      idempotency_key: ik
    )
    if result.intermittent_error?
      reattempt!(wait: 5.seconds)
    elsif result.invalid_request?
      hero.failed!
      cancel!
    else
      hero.processing!
      # and then do nothing and proceed to the next step
    end
  end

  step :confirm_payment do
    ik = hero.idempotency_key # The `hero` in this case is a Payment, not the User
    payment_details = PaymentProvider.details(idempotency_key: ik)
    case payment_details.state
    when :complete
      hero.complete!
      PaymentSentNotification.notify_sender_of_success(hero.sender).deliver_later
    when :failed
      hero.failed!
      PaymentSentNotification.notify_sender_of_failure(hero.sender).deliver_later
    else
      logger.info {"Payment #{hero} still confirming" }
      reattempt!(wait: 30.seconds) if payment_details.state == :processing
    end
  end
end
```

Here, we first initiate a payment using an idempotency key, and then poll for its completion or failure repeatedly. When a payment fails or succeeds, we notify the sender and finish the `Journey`. Note that this `Journey` is of a _payment,_ not of the user. A user may have multiple Payments in flight, each with their own `Journey` being tracket transactionally and correctly.

## Flow control within steps

Inside a step, you currently can use the following flow control methods:

* `cancel!` - cancel the Journey immediately. It will be persisted and moved into the `canceled` state.
* `reattempt!` - reattempt the Journey immediately, triggering it asynchronously. It will be persisted
    and returned into the `ready` state. You can specify the `wait:` interval, which may deviate from
    the wait time defined for the current step
* `pause!` - pause the Journey either within a step or outside of one. This moves the Journey into the `paused` state.
    In that state, the journey is still considered unique-per-hero (you won't be able to create an identical Journey)
    but it will not be picked up by the scheduled step jobs. Should it get picked up, the step will not be performed.
    You have to explicitly `resume!` the Journey to make it `ready` - once you do, a new job will be scheduled to
    perform the step.

> [!IMPORTANT]  
> Flow control methods use `throw` when they are called from inside a step. Unlike Rails `render` or `redirect` that require an explicit
> `return`, the code following a `reattempt!` or `cancel!` within the same scope will not be executed, so those methods may only be called once within a particular scope.

You can't call those methods outside of the context of a performing step, and an exception is going to be raised if you do.


## Transactional semantics within steps

Getting the transactional semantics _right_ with a system like stepper_motor is crucial. We strike a decent balance between reliability/durability and performance, namely:

* The initial "checkout" of a `Journey` for performing a step is lock-guarded
* Inside the lock guard the `state` of the `Journey` gets set to `performing` - you can see that a journey is currently being performed, and no other processes will ever checkout that same `Journey`
* The transaction is only applied at the start of the step, _outside_ of that step's block. This means that you can perform long-running operations in your steps, as long as they are idempotent - and manage transactions inside of the steps.

We chose to make stepper_motor "transactionless" inside the steps because the operations and side effects we usually care about would be long-running and performing HTTP or RPC requests. Had the step been wrapped with a transaction, the transaction could become very long - creating a potential for a fairly large rollback in case the step fails.

Another reason why we avoid forced transactions is that if, for whatever reason, you need multiple idempotent actions _inside_ of a step the outer transaction would not permit you to have those. We prefer leaving that flexibility to the end application.

Should you need to wrap your entire step in a transaction, you can do so manually.

## ActiveJob and transactions

We recommend using a "co-committing" ActiveJob adapter with stepper_motor (an adapter which has the queue in the same RDBMS as your business model tables). Queue adapters that support this:

* [gouda](https://github.com/cheddar-me/gouda)
* [good_job](https://github.com/bensheldon/good_job)
* [solid_queue](https://github.com/rails/solid_queue) - with the same database used for the queue as the one used for Journeys

While Rails core admittedly [insists on the stylistic choice of denying the users the option of co-committing their jobs](https://github.com/rails/rails/pull/53375#issuecomment-2555694252) we find this a highly inconsiderate choice, which has highly negative consequences for a system such as stepper_motor - where durability is paramount. Having good defaults is appropriate, but not removing a crucial affordance that a DB-based job queue provides is downright user-hostile.

In the future, stepper_motor _may_ move to a transactional outbox pattern whereby we emit events into a separate table and whichever queue adapter you have installed will be picking those messages up.

For its own "trigger" job (the `PerformStepJob` and its versions) stepper_motor is configured to commit it with the Journey state changes, within the same transaction.

This is done for the following reasons:

* Not having the Journey with up-to-date state in teh DB when the job performs will lead to the job silently skipping, which is undesirable
* But having the app crash between the Journey state committing and the trigger job committing is even less desirable. This would lead to jobs hanging in the `ready` state indefinitly, seemingly at random.

## Saving side-effects of steps

Right now, stepper_motor does not provide any specific tools for saving side-effects or inputs of a step or of the entire `Journey` except for the related `hero` record. The reason for that is that side effects can take many shapes. A side effect may be a file output to S3, a record saved into your database, a file on the filesystem, or a blob of JSON carried around. The way this data has to be persisted can also vary. For the moment, we don't see a good _generalized_ way to persist those side effects aside of the factual outputs. So:

* A record of the fact that a step has been performed to completion is sufficient to not re-enter that step
* If you need repeatable, but idempotent steps - idempotency is on you

## Unique Journeys

By default, stepper_motor will only allow you to have one active `Journey` per journey type for any given specific `hero`. This will fail, either with a uniqueness constraint violation or a validation error:

```ruby
SomeJourney.create!(hero: user)
SomeJourney.create!(hero: user)
```

Once a `Journey` becomes `canceled` or `finished`, another `Journey` of the same class can be created again for the same `hero`. If you need to create multiple `Journeys` of the same class for the same `hero`, pass the `allow_multiple` attribute set to `true`. This value gets persisted and affects the inclusion of the `Journey` into a partial index that enforces uniqueness:

```ruby
SomeJourney.create!(hero: user, allow_multiple: true)
SomeJourney.create!(hero: user, allow_multiple: true)
```

## Querying for Journeys already created

Frequently, you will encounter the need to select `heroes` to create `Journeys` for. You will likely want to create `Journeys` only for those `heroes` who do not have these `Journeys` yet. You can use a shortcut to generate you the SQL query to use in a `WHERE NOT EXISTS` SQL clause. Usually, your query will look something like this:

```sql
SELECT users.* FROM users WHERE NOT EXISTS (SELECT 1 FROM stepper_motor_journeys WHERE type = 'YourJourney' AND hero_id = users.id)
```

To make this simpler, we offer a special helper method:

```ruby
YourJourney.presence_sql_for(User) # => SELECT 1 FROM stepper_motor_journeys WHERE type = 'YourJourney' AND hero_id = users.id
```

## What to pick as the hero

If your use case requires complex associations, you may want to make your `hero` a record representing the business process that the `Journey` tracks, instead of making the "actor" (say, an `Account`) the hero. This will allow for better granularity and better-looking code that will be easier to understand.

So instead of doing this:

```ruby
class PurchaseJourney < StepperMotor::Journey
  step :start_checkout do
    hero.purchases.create!(sku: ...)
  end
end

PurchaseJourney.create!(hero: user, allow_multiple: true)
```

try this:

```ruby
class PurchaseJourney < StepperMotor::Journey
  step :start_checkout do
    hero.checkout_started!
  end
end

purchase = user.purchases.create!(sku: ...)
PurchaseJourney.create!(hero: purchase)
```

## Forward-scheduling or in-time scheduling

There are two known approaches for scheduling jobs far into the future. One approach is "in-time scheduling" - regularly run a _scheduling task_ which performs the steps that are up for execution. The code for such process would look roughly looks like this:

```ruby
Journey.where("state = 'ready' AND next_step_to_be_performed_at <= NOW()").find_each(&:perform_next_step!)
``` 

This scheduling task needs to be run with a high-enough frequency which matches your scheduling patterns.

Another is "forward-scheduling" - when it is known that a step of a journey will have to be performed at a certain point in time, enqueue a job which is going to perform the step:

```ruby
PerformStepJob.set(wait: journey.next_step_to_be_performed_at).perform_later(journey)
```

This creates a large number of jobs on your queue, but will be easier to manage. stepper_motor supports both approaches, and you can configure the one you like using the configuration:

```ruby
StepperMotor.configure do |c|
  # Use jobs per journey step and enqueue them early
  c.scheduler = StepperMotor::ForwardScheduler.new
end
```

or, for cyclic scheduling (less jobs on the queue, but you need a decent scheduler for your background jobs to be present:

```ruby
StepperMotor.configure do |c|
  # Check for jobs to be created every 5 minutes
  c.scheduler = StepperMotor::CyclicScheduler.new((cycle_duration: 5.minutes)
end
```

If you use in-time scheduling you will need to add the `StepperMotor::ScheduleLoopJob` to your cron jobs, and perform it frequently enough. Note that having just the granularity of your cron jobs (minutes) may not be enough as reattempts of the steps may get scheduled with a smaller delay - of a few seconds, for instance.

## Naming steps

stepper_motor will name steps for you. However, using named steps is useful because you then can insert steps between existing ones, and have your `Journey` correctly identify the right step. Steps are performed in the order they are defined. Imagine you start with this step sequence:

```ruby
step :one do
  # perform some action
end

step :two do
  # perform some other action
end
```

You have a `Journey` which is about to start step `one`. When the step gets performed, stepper_motor will do a lookup to find _the next step in order of definition._ In this case the step will be step `two`, so the name of that step will be saved with the `Journey`. Imagine you then edit the code to add an extra step between those:

```ruby
step :one do
  # perform some action
end

step :one_bis do
  # some compliance action
end

step :two do
  # perform some other action
end
```

Your existing `Journey` is already primed to perform step `two`. However, a `Journey` which is about to perform step `one` will now set `one_bis` as the next step to perform. This allows limited reordering and editing of `Journey` definitions after they have already begun.

So, rules of thumb:

* When steps are recalled to be performed, they get recalled _by name._
* When preparing for the next step, _the next step from the current in order of definition_ is going to be used.

## Using instance methods as steps

You can use instance methods as steps by passing their name as a symbol to the `step` method:

```ruby
class Erasure < StepperMotor::Journey
  step :erase_attachments
  step :erase_emails

  def erase_attachments
    hero.uploaded_attachments.find_each(&:destroy)
  end

  def erase_emails
    while hero.emails.count > 0
      hero.emails.limit(5000).delete_all
    end
  end
end
```

Since a method definition in Ruby returns a Symbol, you can use the return value of the `def` expression
to define a `step` immediately:

```ruby
class Erasure < StepperMotor::Journey
  step def erase_attachments
    hero.uploaded_attachments.find_each(&:destroy)
  end

  step def erase_emails
    while hero.emails.count > 0
      hero.emails.limit(5000).delete_all
    end
  end
end
```
## Exception handling inside steps

> [!IMPORTANT]
> Exception handling in steps is in flux, expect API changes.

When performing the step, any exceptions raised from within the step will be stored in a local
variable to allow the Journey to be released as either `ready`, `finished` or `canceled`. The exception
will be raised from within an `ensure` block after the persistence of the Journey has been taken care of.

By default, an exception raised inside a step of a Journey will _pause_ that Journey. This is done for a number of reasons:

* An endlessly reattempting step can cause load on your infrastructure and will never stop retrying
* Since at the moment there is no configuration for backoff, such a step is likely to hit rate limits on the external resource it hits
* It is likely a condition that was not anticipated when the Journey was written, thus a blind reattempt is unwise.

While we may change this in future versions of `stepper_motor`, the current default is thus to `pause!` the Journey if an unhandled
exception occurs. You can, however, switch it to `reattempt!` or `cancel!` a Journey should a particular step raise. This is configured per step:

```ruby
class Erasure < StepperMotor::Journey
  step :initiate_deletion, on_exception: :reattempt! do
    # ..Do the requisite work
  end
end
```

or, if you know that the correct action is to cancel the journey - specify it explicitly (even though it is the default at the moment)

```ruby
class Erasure < StepperMotor::Journey
  step :initiate_deletion, on_exception: :cancel! do
    # ..Do the requisite work
  end
end
```

We recommend handling exceptions you care about explicitly inside your step definitions. This allows for
more fine-grained error matching and does not disrupt the step execution. If you want to register the
exceptions you `rescue` inside steps, make use of the `Rails.error.report` [method](https://guides.rubyonrails.org/error_reporting.html#manually-reporting-errors)

```ruby
class Payment < StepperMotor::Journey
  step def initiate_payment
    payment = hero
    client = PaymentProvider::Client.new
    client.initiate_payment(idempotency_key: payment.id, amount: payment.amount_cents, recipient: payment.recipient.id)
  rescue PaymentProvider::ConfigurationError => e
    payment.failed!
    Rails.error.report(e)
    cancel! # Without reconfiguration the payment will never initiate
  rescue PaymentProvider::RateLimitExceeded => e
    reattempt! wait: e.retry_after
  rescue PaymentProvider::InsufficientFunds => e
    payment.sender.add_compliance_note("Halted payment due to insufficient funds")
    pause!
  rescue PaymentProvider::Timeout
    reattempt! wait: rand(0.0..5.0) # Add some jitter
  rescue PaymentProvider::AccountBlocked
    paymend.failed!
    cancel! # Do not even report the error - the account has been closed and will stay closed forever
  end
end
```


