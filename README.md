# StepperMotor

Is a useful tool for running stepped or iterative workflows inside your Rails application.

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
```



## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/stepper_motor.
