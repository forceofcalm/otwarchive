@users @tag_wrangling @admin
Feature: Tag wrangling

  Scenario: Admin can rename a tag

    Given I am logged in as an admin
      And a fandom exists with name: "Amelie", canonical: false
    When I edit the tag "Amelie"
      And I fill in "Synonym of" with "Amélie"
      And I press "Save changes"
    Then I should see "Amélie is considered the same as Amelie by the database"
      And I should not see "Tag was successfully updated."
    When I fill in "Name" with "Amélie"
      And I press "Save changes"
    Then I should see "Tag was updated"
      And I should see "Amélie"
      And I should not see "Amelie"

  Scenario: Admin can remove a user's wrangling privileges from the manage users page (this will leave assignments intact)

    Given the tag wrangler "tangler" with password "wr@ngl3r" is wrangler of "Testing"
    When I am logged in as an admin
      And I am on the manage users page
    When I fill in "Name or email" with "tangler"
      And I press "Find"
    Then I should see "tangler" within "#admin_users_table"
    When I uncheck the "Tag Wrangler" role checkbox
      And I press "Update"
    Then "tangler" should not be a tag wrangler
      And "Testing" should be assigned to the wrangler "tangler"

  Scenario: Admin can remove a user's wrangling assignments

    Given the tag wrangler "tangler" with password "wr@ngl3r" is wrangler of "Testing"
    When I am logged in as an admin
      And I am on the wranglers page
      And I follow "x"
    Then "Testing" should not be assigned to the wrangler "tangler"
    When I edit the tag "Testing"
    Then I should see "Sign Up"
    
