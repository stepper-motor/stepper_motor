# stepper_motor

Is a useful tool for running stepped or iterative workflows inside your Rails application.

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

  step :onboarding_complete, wait: 15.days do
    OnboardingCompleteMailer.onboarding_complete_email(hero).deliver_later
  end
end

SignupJourney.create!(hero: current_user)
```

Want to know more? Dive into the [manual](/manual/MANUAL.md) we provide.

## Installation

Add the gem to the application's Gemfile, and then generate and run the migration

    $ bundle add stepper_motor
    $ bundle install
    $ bin/rails g stepper_motor:install --uuid # Pass "uuid" if you are using UUID for your primary and foreign keys
    $ bin/rails db:migrate

## 🚧 stepper_motor is undergoing active development

For versions 0.1.x stepper_motor is going to undergo active development, with infrequent - but possible - API changes and database schema changes. Here's what it means for you:

* When you update the gem you must run `bin/rails g stepper_motor:install --skip` to add any migrations you may need
* You have to ensure the application running a new version has the DB schema already updated. If your deployment does not allow for automatic
  sequential migrate-then-deploy, deploy the migrations first.

Starting with versions 0.2.x and up, stepper_motor will make the best possible effort to allow operation without having applied the recent migrations.

## Development

After checking out the repo, run `bundle` to install dependencies. The development process from there on is like any other gem.

## Is it any good?

[Yes.](https://news.ycombinator.com/item?id=3067434)

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/stepper-motor/stepper_motor.
