class Page
	def initialize(driver)
		@se = driver
	end

	def get_current_url
		wait = Selenium::WebDriver::Wait.new(
			:timeout => 60, :interval => 1, :ignore => [Net::ReadTimeout])
		wait.until { @se.current_url }
	end

	def get_title
		@se.title
	end

	def go_back
		@se.navigate.back 
	end
end

class GoogleHome < Page
	attr_reader :locs

	def initialize(driver)
		super(driver)
		@wait = Selenium::WebDriver::Wait.new(:timeout => 15)
		@locs = {
			search_input: {css: 'input[name=q]'}, 
			search_button: {css: 'div.FPdoLc input[name="btnK"]'},
		}
	end

	def open_page
		@se.get('https://www.google.com')
	end

	def fill_search_term(search_term)
		@se.find_element(locs[:search_input]).send_keys(search_term)
	end

	def submit_search
		@wait.until { @se.find_element(locs[:search_button]) }
		@se.find_element(locs[:search_button]).click
	end

end

class GoogleSearchResults < Page
	attr_reader :locs
	
	def initialize(driver)
		super(driver)
		@wait = Selenium::WebDriver::Wait.new(:timeout => 15)
		@locs = {
			results_list: {css: '.srg'},
			results_item: {css: '.srg .rc'},
			result_header: {css: '.r'},
			result_cite: {css: 'cite'},
			also_asked_question_set: {xpath: '//h2[text()="People also ask"]/following-sibling::*' },
			also_asked_question: {xpath: '//*[contains(@class, "cbphWd")]' },
			knowledge_panel: {css: '.knowledge-panel'},
			knowledge_panel_attribute: {css: '.Z1hOCe'},
		}
	end

	def wait_until_page_loads
		@wait.until { @se.find_element(@locs[:results_item]) }
	end

	# Get search results elements 
	#   Returns array of web elements - the paragraphs on the search results page
	def get_search_results
		wait_until_page_loads
		@se.find_elements(@locs[:results_item])
	end

	def get_also_asked_questions
		wait_until_page_loads
		question_block = @se.find_element(@locs[:also_asked_question_set])
		question_block.find_elements(@locs[:also_asked_question])
	end

	def get_knowledge_panel
		wait_until_page_loads
		@se.find_element(@locs[:knowledge_panel])
	end

	def get_knowledge_panel_attributes
		panel = get_knowledge_panel
		panel.find_elements(@locs[:knowledge_panel_attribute]) 
	end

	# click the link in a search result header  
	#   parameter result - web element, assumed to be a search result 
 	def click_result_header(result)
	 	wait = Selenium::WebDriver::Wait.new(:timeout => 60, :interval => 1)

 		old_url = get_current_url
 		link = get_result_header_link(result)
	 	href = link.attribute('href')
 		
 		begin 
 			# elements that are lower on page might not be in view without scrolling
	 		p=link.location_once_scrolled_into_view
	 		@se.execute_script("window.scrollTo(#{p.x},#{p.y})")

	 		link.send_keys(:return)  # an alternative to click which shouldn't block or wait for something
	 		#link.click

	 		# wait for URL to change before continuing
	 		wait.until { old_url != get_current_url }

		# ignore errors associated with slow connection and page loading
	 	rescue Net::ReadTimeout, Selenium::WebDriver::Error::TimeOutError => e
	 		print " '#{e.message}' error ignored on link #{href} "
	 	end
 	end

	# parameter result - web element, assumed to be a search result
	# returns the link in the header node
	def get_result_header_link(result)
		result.find_element(@locs[:result_header]).find_element({css: 'a'})
	end

	# parameter result - web element, assumed to be a search result
	# returns cite's text
	def get_result_cite_text(result)
		result.find_element(@locs[:result_cite]).text
	end

end
