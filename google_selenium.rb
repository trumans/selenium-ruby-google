# 
# To run tests
# $ ruby google_selenium.rb <browser>
#     where <browser> is one of the supported browsers
# $ ruby google_selenium.rb <browser> -n <test_case>
#     where <test_case> is one of the test_* methods 
# $ ruby google_selenium.rb <browser> -n=/<pattern>/
#     where <pattern> is a regex that can match test case names

require "selenium-webdriver"
require "test/unit"
require "byebug"

require_relative "pages"

$argv = ARGV.dup

Test::Unit.at_start do

	# Get browser argument from command line
	supported_browsers = ['chrome', 'firefox']

  b = supported_browsers & $argv
	if b.length > 0
      $browser_arg = b[0]
  else
  		msg = "Expected one of the following: " + supported_browsers.to_s[1..-2]
  		raise ArgumentError.new(msg)
  		exit
	end

end

class GoogleTest < Test::Unit::TestCase

  def setup
  	case $browser_arg
  	when 'chrome'
	  	browser = :chrome
  		driver_path = '/selenium_browser_drivers/chromedriver'
  	when 'firefox'
	  	browser = :firefox
  		driver_path = '/selenium_browser_drivers/geckodriver'
  	else
		  raise ArgumentError.new("Unexpected browser argument '#{$browser_arg}'") 
		  exit 		
  	end
	  @se = Selenium::WebDriver.for browser, :driver_path => driver_path
  end

  def teardown
  	@se.quit
  end

  def test_search_person_first_and_last_name
  	submit_search("buster keaton")
  	verify_search_results_page_contains("buster", "keaton")
  	verify_knowledge_panel("born", "died", "height")
  	verify_also_asked_questions("buster", "keaton")
  end

  def test_search_person_last_and_first_name
  	submit_search("keaton buster")
  	verify_search_results_page_contains("buster", "keaton")
  	verify_knowledge_panel("born", "died", "height")
  end

  def test_search_results_animal
  	submit_search("octopus")
  	verify_search_results_page_contains("octopus")
  	verify_also_asked_questions("octopus")
  	verify_knowledge_panel("lifespan", "phylum", "scientific name")
  end

  def test_search_results_two_words
  	submit_search("disneyland", "submarine")
  	verify_search_results_page_contains("disneyland", "submarine")
  	verify_knowledge_panel("opened", "duration")
  end

  def test_search_results_country
  	submit_search("dominica")
  	verify_search_results_page_contains("dominica")
  	verify_knowledge_panel("capital", "language", "population")
  end

  def test_search_chemical_element
  	submit_search("element helium")
  	verify_search_results_page_contains("element", "helium")
  	verify_knowledge_panel("symbol", "atomic mass", "atomic number", "electrons")
  end

  def submit_search(*search_terms)
  	page = GoogleHome.new(@se)
  	search_input = search_terms.join(" ")
  	puts "* Search for '#{search_input}'"
    page.open_page
  	page.fill_search_term(search_input)
  	page.submit_search

  	page = GoogleSearchResults.new(@se)
	  page.wait_until_page_loads
  end

  def verify_search_results_page_contains(*search_terms)

    search_terms_regex = search_terms.map { |search|
	   Regexp.new(search, Regexp::IGNORECASE) }

    results_page = GoogleSearchResults.new(@se)
    results = results_page.get_search_results
    result_count = results.size

    # verify each result displays all search terms
    results.each { |item| 
      search_terms_regex.each { |regex| assert_match(regex, item.text) }
    }

    # verify link in header opens same page as 'cite' line
    (0...result_count).each { |idx|
      #print "#{search_terms.inspect}: "
      print "index #{idx} "
		  results = results_page.get_search_results # need fresh page each iteration
		  cite_url = strip_http(results_page.get_result_cite_text(results[idx]))

		  if skip_url(cite_url)
        puts("skipping #{cite_url}")
        next
		  end

      results_page.click_result_header(results[idx])
      dest_page = Page.new(@se)  # confirming generic page data
		  dest_url = strip_http(dest_page.get_current_url)

      assert_expected_destination_url(cite_url, dest_url)
      puts "title: #{dest_page.get_title} "

      sleep(0.75)
		  dest_page.go_back
		  results_page.wait_until_page_loads  # wait for results page
    }
  end

  # Assert the URL in the cite matches the URL that was reached
  # Parameters:
  #   cite_url - URL from the cite element
  #   dest_url - URL actually reached
  def assert_expected_destination_url(cite_url, dest_url)
    # verify destination url matches cite line
    if cite_url.include?(" › ")
      # cite is reformated to suggest a hierachy. Compare before "›"
      print "(cite has › ) "
      cite_domain = cite_url.match(/(.*?) › /)[1]
      assert_equal(cite_domain, dest_url[0...cite_domain.length])
    elsif cite_url.include?('...')
      # cite replaced parts of URL with '...'.  Use regex with .+
      print "(cite has ...) "
      r = cite_url.gsub('...', '.+')
      cite_regex = Regexp.new(r, Regexp::IGNORECASE)
      assert_match(cite_regex, dest_url)
    else
      # otherwise URLs are expected to match exactly  
      print "(cite is actual url) "
      assert_equal(cite_url, dest_url)
    end
  end

  # Assert Also Asked Questions box contains certain text
  # Parameters
  #   search_terms - one or more strings expected in each questions
  def verify_also_asked_questions(*search_terms)
    page = GoogleSearchResults.new(@se)
    questions = page.get_also_asked_questions
    puts "verify Also Asked has #{search_terms.inspect}"
    assert(questions.length > 1, "expected one or more questions")
    questions.each { |q|
		  txt = q.text
		  #puts " also asked: " + txt
		  search_terms.each { |s|
        assert(txt.downcase.include?(s), "expected '#{s}' in '#{txt}'")
		  }
	}
  end

  # Assert Knowledge Panel contains specified table entries
  # Parameter
  #   expected_attributes - one or more strings expected in a label 
  def verify_knowledge_panel(*expected_attributes)
  	page = GoogleSearchResults.new(@se)
  	els = page.get_knowledge_panel_attributes
  	attrs_found = els.map { |el| el.text.downcase }
  	puts "verify knowledge panel has #{expected_attributes.inspect}."
  	# each expected attribute should be in the found attributes
  	expected_attributes.map { |exp_attr| 
  		assert( attrs_found.any? { |a| a.include?(exp_attr) }, 
  			    "expected '#{exp_attr}' to be in found attributes: #{attrs_found.inspect}" )
  	}
  end

  ##################### 
  # Support functions
  #####################

  # Remove url parts that are not relevant to matching
  #    scheme (http, https)
  #    trailing /, #
  # Parameter
  #   url - url string to be "cleaned"
  # Returns url with irrelevant parts removed
  def strip_http(url)
      
    # remove scheme
    if url.start_with?('http://')
      dest_url = url[7..-1]
    elsif url.start_with?('https://')
      dest_url = url[8..-1]
    else 
      dest_url = url
    end

    # remove trailing "meaningless" characters
    if dest_url.end_with?('/')
      dest_url = dest_url[0..-2]
    end

    if dest_url.end_with?('#')
      dest_url = dest_url[0..-2]
    end

    return dest_url
  end

  # Return whether the URL should be skip because domain is problematic for automation
  #   Parameter url - string
  #   Returns true if url contains the domain to ignore otherwise return false 
  def skip_url(url)
    # domains to skip
    #   www.britannica.com - sometimes has ad window that overlays. 
    #   www.montereybayaquarium.org - redirects to itself, which requires back twice to return to search results
    #   www.livescience.com - causes intermittent timeouts.
    urls = [
      'www.britannica.com', 'www.montereybayaquarium.org', 'www.livescience.com'
    ]
    for u in urls
      return true if url.include? u
    end
    return false
  end

end
